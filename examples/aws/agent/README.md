# agent

The Lerian agent, installed into the cluster the `eks` root created.

The agent is a process that runs inside the customer's cluster, makes **outbound
only** connections to the Lerian control plane, and executes the Helm operations
the control plane assigns it — install, upgrade, rollback, uninstall, diff,
preflight, status. One per cluster.

It does **not** provision cloud infrastructure. The VPC, the cluster and the
datastores belong to the other roots here; work items asking the agent for
infrastructure are refused.

```
release name    lerian-agent          (fixed by the chart, not by this root)
namespace       lerian-system         (var.namespace)
identity Secret lerian-agent-identity (kept on uninstall)
chart           oci://ghcr.io/lerianstudio/agent-helm
```

## Why Terraform and not `helm install`

A release in state is reconciled on every apply: the chart version, the managed
namespaces and the control plane URL are whatever this code says they are. A
hand-run `helm install` is true on the day somebody ran it.

It also means removing this root removes the agent, rather than leaving one
behind that nobody remembers installing.

## Order

```
vpc → eks → agent
```

It finds the cluster with a data source — not through remote state, which would
couple this root to where that state is kept as well as to what it holds.

No kubeconfig is read. The endpoint and the CA come from the data source, so an
apply reaches the cluster named in `cluster_name` — never "whichever context the
operator last selected".

The token comes from `aws eks get-token`, run by the Helm provider when it opens
the connection. An EKS token lasts 15 minutes, so reading one during the plan
would expire it under any approval gate; this way it is minted during the apply,
every time. **The machine that applies needs the AWS CLI on its PATH**, with the
same credentials Terraform is using.

## Running it

Nothing here is auto-loaded. `backend.tf` ships with placeholders, and
`agent.tfvars-example` is an example file, not a `.auto.tfvars` — Terraform
reads neither until you say so.

```bash
# 1. Point the backend at the bucket the backend root created.
#    Edit backend.tf: bucket, key, region, dynamodb_table.

# 2. Copy the example and fill it in.
cp agent.tfvars-example agent.tfvars   # gitignored; it holds the credential

# 3. Init, plan, apply.
terraform init
terraform plan  -var-file=agent.tfvars
terraform apply -var-file=agent.tfvars
```

Keep the credential out of `agent.tfvars` if you would rather it never sat on
disk: `export TF_VAR_agent_token=...` for the run, or put it in a Secret
yourself and name that Secret in `existing_secret_name` — see below.

## The credential

The agent authenticates to the control plane with one of two tokens, and the
chart refuses to render without one:

| | where it comes from | `agent_id` |
|---|---|---|
| **enrollment** | `POST /api/tenants/:id/agents/enrollments` | empty — the agent is told its identity when it redeems the token, and keeps it in `lerian-agent-identity` |
| **per-agent** | `POST /api/tenants/:id/agents` | required, from the same response |

An enrollment token is single-use and short-lived, which is what makes it safe
to hand to a cluster that does not exist yet.

**Either form reaches Terraform state.** `existing_secret_name` is the way that
does not: put the credential in a Secret by another route and name it here, and
this root only references it.

## Variables worth deciding

| variable | why it matters |
|---|---|
| `control_plane_url` | https:// unless `allow_insecure_http`; the agent sends its bearer token on every request |
| `managed_namespaces` | every namespace the agent may install into. **Each must already exist**, and adding one later needs another apply |
| `chart_version` | empty by default, which installs the newest published chart. Pin it for a cluster you intend to keep: a version in the variables is the only way two applies of this code produce the same agent |
| `image_repository` + `allowed_image_registries` | change them together. The agent refuses a self-update from a registry it was not told about, and the chart's default allows `ghcr.io/lerianstudio` only |
| `image_digest` | set after the control plane has moved the agent to a newer build, or the next apply puts the old tag back |

Four preconditions run at plan time, so a mistake names the variable to fix
rather than a line inside a chart template: a missing credential, an `agent_id`
sent with an enrollment token, a cleartext URL without the flag, and an image
repository outside its own allowlist.

## After apply

```bash
kubectl -n lerian-system get pods -l app.kubernetes.io/name=agent
kubectl -n lerian-system logs deploy/lerian-agent | grep "sent initial heartbeat"
```

The control plane shows the agent connected once that heartbeat lands. To check
the credential without side effects the image takes `--self-check`; do **not**
call `/work/poll` by hand, which claims a work item.

## Requirements

Kubernetes >= 1.33 — the chart's `kubeVersion`, and Helm refuses below it.
