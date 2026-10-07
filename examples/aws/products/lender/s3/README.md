# `products/lender/s3`

The lender's own custody bucket, `lender-{env}-issuance-custody-{account_id}`:
the value of `ISSUANCE_CUSTODY_S3_BUCKET`. Unset, the lender keeps the routes
mounted and answers 503 instead of emitting a document with no custody.

## What it holds

One bucket, three disjoint key namespaces under the tenant prefix
lib-commons `tenant-manager/s3` applies from the request context:

| Key | Contents |
|---|---|
| `{tenantId}/instruments/...` | rendered credit instruments (CCB PDFs) |
| `{tenantId}/assignment-dossiers/...` | cessão receivable dossiers |
| `{tenantId}/assignment-terms/...` | assignment (endorsement) terms |

## What the lender uses from the policy

`_modules/s3-bucket` emits `lender-{env}-issuance-custody-s3-access`. The
lender calls `PutObject` and `GetObject` on `bucket/*` for every write and
read, plus `ListBucket` and `DeleteObject` for the instrument custody sweeper
(`JOBS_INSTRUMENT_CUSTODY_SWEEP_ENABLED`, off by default), which removes
PII-bearing orphans no row references. A bucket with `kms_key_arn` set also
gets the KMS grant on that key.

## No Object Lock by default

The lender writes plain `PutObject` with no retention, rewrites the same key on
a crash retry, and deletes orphans. Object Lock is settable only at bucket
creation and cannot be removed; with it on, the module withholds
`DeleteObject` and the sweeper stops working. The `object_lock_*` options stay
on the bucket map for a deployment that decides to retain these documents as
WORM, before its first apply.

## One role

This root runs with `irsa_enabled = false`: it creates the bucket and the
attachable policy, and no role. `../secrets` attaches the policy to
`lender-{env}-secrets-irsa` through `additional_policy_names`, because a
ServiceAccount carries exactly one `role-arn` annotation. **Apply this root
before `../secrets`**: an attachment to a policy that does not exist fails with
`NoSuchEntity`. With no role there is no OIDC lookup, so this root does not
depend on `infra-base/eks`.

## Helm handoff

`helm_values` emits dotted paths of helm-internal `charts/lender`:

- `lender.configmap.ISSUANCE_CUSTODY_S3_BUCKET`: the bucket.
- `lender.configmap.ISSUANCE_CUSTODY_S3_REGION`: the lender builds this client
  with that region and defaults it to `us-east-1`; a bucket in another region
  fails every call with `PermanentRedirect`.
