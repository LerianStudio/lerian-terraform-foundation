# `products/iam/github-oidc-s3-upload`

The identities release pipelines use to publish migrations into this account's
migrations bucket: one GitHub identity provider for the account, and one role per
listed repository.

The tenant manager reads a service's SQL migrations out of an S3 bucket in the
**application** account, under `{channel}/{service}/{module}/{dbType}/`. The
files get there from the service's release pipeline: go-release's `S3 Upload`
job copies them on every tag.

That job does **not** assume a role from another AWS account. It asks GitHub for
a fresh OIDC token and calls `sts:AssumeRoleWithWebIdentity` with
`audience=sts.amazonaws.com` — so the principal the trust policy has to name is
**GitHub's OIDC provider**, and it has to exist in this account first.

Applies in the account that owns the bucket, **once**, as environment `prd`.

## Three parts, all of them load-bearing

1. **GitHub's OIDC issuer as an identity provider in this account.** Without it,
   a token minted by GitHub Actions is not a principal this account recognises
   and no trust policy can name it. No thumbprint is pinned: since 2023 AWS
   validates `token.actions.githubusercontent.com` against its own trust store
   and ignores the recorded value.
2. **Per repository, a trust policy pinning `:sub` to the refs listed for that
   repository, and `:aud`.** Every GitHub Actions token in the world is signed by
   the same issuer, so `:sub` is the entire boundary: one
   `repo:OWNER/REPO:ref:{ref}` per entry of `refs`, under `StringLike`. The only
   wildcard allowed is the whole tag glob `refs/tags/*`, the default, and it is
   on the **tag name**, never on the repository. A branch is named in full and
   admits only itself. A pull request carries a different subject and is
   refused, which is what keeps a workflow edited in a fork's pull request away
   from the bucket.
3. **Per role, one inline policy, one verb.** `s3:PutObject` over
   `{channel}/{service}/*` for the three release channels and each service that
   repository publishes, and nothing else. The service is the folder go-release
   writes under, usually the repo name but not always: Midaz publishes as
   `ledger`.

## Why one role per repository, not one role for all

A role's permissions cannot tell which repository assumed it: GitHub's token
carries no session tags, and `:sub` is visible to the trust policy only. One
shared role would hand every listed repository the union of the prefixes, so one
release could overwrite another service's migrations — which the tenant manager
then runs against that service's database. The identity provider is shared
because AWS allows one per URL per account; everything after it is per
repository. Adding a repository is a new entry in `github_repositories`, never a
second instance of this root.

## Why the roles live here and not next to the pipelines

They live in the account that **owns the bucket**. That is what makes a bucket
policy unnecessary — an in-account role with `s3:PutObject` is enough, and
`_modules/s3-bucket` does not have to grow a bucket-policy input it has never
needed.

## Why the channels are derived, not configured

go-release picks the top-level folder from the tag's channel:

| tag                         | folder         |
| --------------------------- | -------------- |
| `*-beta*`                   | `development/` |
| `*-rc*`                     | `staging/`     |
| `vX.Y.Z`                    | `production/`  |

An `s3_uploads` entry is **not** conditional on the channel — it runs on every
tag the repository cuts. A service that cuts a beta on each merge to `develop`
writes to `development/` constantly, so a policy listing only `production/`
turns every merge into a red `S3 Upload` job: the step runs under
`set -euo pipefail`, and one `AccessDenied` kills it.

Listing the three folders in a tfvars would make "all the channels, and only the
channels" something a reviewer has to remember. The root derives them, and the
cost of the folders nothing reads today is zero.

## What is deliberately absent

- **`s3:DeleteObject`.** The tenant manager decides what to run by comparing the
  migrations a tenant has applied against the ones available in the bucket.
  Removing a `.sql` a tenant already applied puts a hole in that comparison. A
  release pipeline only ever adds files.
- **`s3:ListBucket`.** go-release copies each file by key. Listing is the
  reader's job, and the reader is not this identity.
- **A thumbprint.** See above; a pinned fingerprint here would rot on rotation
  and read as a control that is not one.

## Deploy order

1. the bucket — `products/tenant-manager/s3`, here;
2. **this root**;
3. the `aws_role_arn` field of the `s3_uploads` entry in each repository's
   `release.yml`, set to that repository's entry of the `role_arns` output.

Until step 3 lands for a repository, nothing assumes its role.

> The organisation secret `AWS_MIGRATIONS_ROLE_ARN` must also reach the
> repository. go-release's `Configure AWS credentials` step runs before the loop
> over `s3_uploads` entries, so an empty secret kills the job before any entry —
> including the entries that carry their own `aws_role_arn`.

## Trusting protected branches instead of tags

```hcl
github_repositories = {
  "LerianStudio/br-consignado-gw" = {
    role_name = "consignado-github-oidc-s3-upload"
    services  = ["br-consignado-gw"]
    refs      = ["refs/heads/main", "refs/heads/release-candidate"]
  }
}
```

That role admits exactly `repo:LerianStudio/br-consignado-gw:ref:refs/heads/main`
and `…:ref:refs/heads/release-candidate`; a tag push is refused. The shared
upload workflow writes a `main` run to `production/` and a `release-candidate`
run to `staging/`. A listed branch is exactly as strong as its protection:
whoever can push to it can upload. Add `refs/tags/*` to the list to keep tags
admitted alongside the branches.

## Inputs

| name                     | required | notes                                                              |
| ------------------------ | -------- | ------------------------------------------------------------------ |
| `environment`            | yes      | `prd` — the roles are a property of the account, not of a stack     |
| `github_repositories`    | yes      | map of `owner/repo` => `{ role_name, services, refs }`. The key and `refs` are that role's trust subjects, one per ref; `services` its object prefixes, never shared between repositories; `role_name` is copied verbatim into that repository's `release.yml` |
| `github_repositories[*].refs` | no  | non-empty list of distinct refs, each exactly `refs/tags/*` or `refs/heads/<branch>` named in full (no `*`, `?`, `[`). Defaults to `["refs/tags/*"]` |
| `migrations_bucket_name` | yes      | a bucket **name**, not an ARN                                       |
| `region`                 | no       | provider endpoint and tags only; S3 ARNs carry no region            |
| `extra_tags`             | no       |                                                                     |

## Rollback

`terraform destroy` of this root is free **only while nothing else trusts the
provider**. The roles and their inline policies are this root's alone —
destroying them breaks the release pipelines that name them, and nothing else.
Removing ONE repository is a tfvars edit: drop its entry and re-apply, and only
its role goes.

The identity provider is not. `token.actions.githubusercontent.com` is an
**account singleton**: AWS refuses a second provider for the same URL, so every
GitHub-OIDC role in this account, here or elsewhere, trusts *this* object. A
destroy that takes it down invalidates their trust policies too — they keep
referring to an ARN that no longer resolves, and every `AssumeRoleWithWebIdentity` against them
fails, with nothing in their own Terraform state having changed to explain it.

So before destroying this root while a role outside it trusts the provider,
that consumer must own the provider first: `terraform state rm` it here and
`terraform import` it there (or move it to a root of its own that both depend
on). Until then, prefer reverting the tfvars and re-applying over a destroy.

## Verification after apply

```bash
aws iam list-open-id-connect-providers | grep -c 'token.actions.githubusercontent.com'   # 1
# then, for each role in `terraform output role_arns`:
aws iam get-role --role-name "$ROLE" \
  --query 'Role.AssumeRolePolicyDocument' | grep -o 'repo:[^"]*'
aws iam get-role-policy --role-name "$ROLE" --policy-name "$ROLE-policy" \
  --query 'PolicyDocument.Statement[].Resource' --output text
```
