# Lerian Terraform Foundation

Terraform templates for the infrastructure the Lerian products run on: the network, the
Kubernetes cluster, and the datastores each product needs.

On **AWS** you run the templates with plain Terraform, one stack at a time. On **GCP and
Azure** they are driven by `./deploy-legacy.sh`, an interactive script over an earlier
layout.

Pick your cloud and follow that section. Read [Important
information](#important-information) before deploying anything to production.

## Support matrix

| Stack | AWS | GCP | Azure | Creates |
| --- | --- | --- | --- | --- |
| `bootstrap` | true | false | partial | Versioned state bucket, lock table, generated backend config |
| `infra-base` | true | true | true | Network with public/private subnets, Kubernetes cluster, DNS zone |
| `shared-resources` | true | false | false | PostgreSQL, DocumentDB, Valkey, RabbitMQ, Kafka: one instance each, shared by every product in the environment |
| `br-consignado-gw` | true | false | false | PostgreSQL, Valkey |
| `br-sfn` | true | false | false | PostgreSQL, Valkey, RabbitMQ, Kafka, S3 |
| `br-sisbajud` | true | false | false | PostgreSQL, Valkey, Kafka |
| `fetcher` | true | false | false | DocumentDB, Valkey, RabbitMQ, S3 |
| `flowker` | true | false | false | DocumentDB, Valkey |
| `matcher` | true | false | false | PostgreSQL, Valkey, RabbitMQ |
| `midaz` | true | false | false | PostgreSQL, DocumentDB, Valkey, RabbitMQ |
| `notifications` | true | false | false | PostgreSQL, Valkey, RabbitMQ |
| `plugin-access-manager` | true | false | false | PostgreSQL, Valkey |
| `plugin-bc-correios` | true | false | false | PostgreSQL, Valkey, RabbitMQ, S3 |
| `plugin-br-bank-transfer` | true | false | false | PostgreSQL, DocumentDB, Valkey, RabbitMQ |
| `plugin-br-payments` | true | false | false | PostgreSQL |
| `plugin-br-pix-direct-jd` | true | false | false | PostgreSQL |
| `plugin-br-pix-indirect-btg` | true | false | false | PostgreSQL, DocumentDB, Valkey |
| `plugin-br-pix-jd` | true | false | false | PostgreSQL |
| `plugin-br-pix-switch` | true | false | false | PostgreSQL, DocumentDB, Valkey, RabbitMQ |
| `plugin-fees` | true | false | false | DocumentDB, Valkey, Kafka |
| `product-console` | true | false | false | DocumentDB |
| `reporter` | true | false | false | DocumentDB, Valkey, RabbitMQ, S3 |
| `tracer` | true | false | false | PostgreSQL, Valkey |
| `lender` | true | false | false | PostgreSQL, Valkey, S3 |

On AWS: PostgreSQL is RDS, DocumentDB is Amazon DocumentDB, Valkey is ElastiCache,
RabbitMQ is AmazonMQ, Kafka is MSK. Each product datastore can be **dedicated** or
resolve the **shared** tier, except S3, which is never shared.

Azure `bootstrap` is partial: `base-resources` creates the storage account for state. Azure
locks state with a blob lease, so there is no lock table. On GCP you create the bucket
yourself, shown below.

**GCP and Azure have no per-product stacks.** They carry generic `cloud-sql`,
`valkey`, `database`, `redis` and `cosmosdb` roots, written for a single deployment and
hardcoded to Midaz. There is no product-scoped root and no shared/dedicated switch, so
the products read false rather than claiming a parity that does not exist.

---

# AWS

Every stack under `examples/aws/` is a separate Terraform root with its own state. You
apply them one at a time, in the order below. The commands use the `dev` environment;
the other two are `stg` and `prd`.

## 1. Prerequisites

- `terraform` 1.9.0 or later. That is the highest `required_version` in the AWS stacks.
- The `aws` CLI and credentials for the AWS account of the environment. The stacks set
  no profile, so Terraform uses the standard AWS credential chain: `AWS_PROFILE`,
  environment variables or an instance role.
- `kubectl` and `helm` for the steps after the cluster exists. Terraform never calls them.
- A checkout of this repository at a release tag:

```bash
git clone --branch <tag> https://github.com/LerianStudio/lerian-terraform-foundation.git
cd lerian-terraform-foundation
```

Every `cd` below is relative to the root of that checkout.

Before every apply, check which account your credentials reach:

```bash
aws sts get-caller-identity --query Account --output text
```

After step 2, that number must match the account id at the end of the bucket name in
`examples/aws/backend/<env>.hcl`.

## 2. Create the state backend

`examples/aws/bootstrap` creates the versioned state bucket
`lerian-tfstate-<env>-<account_id>` and the lock table `lerian-tfstate-lock-<env>`. Run
it once per environment. It cannot keep its state in the bucket it creates, so its state
stays local, in one workspace per environment.

```bash
cd examples/aws/bootstrap
cp envs/dev.tfvars-example envs/dev.tfvars   # set region
terraform init
terraform workspace new dev                   # later runs: terraform workspace select dev
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

The apply writes `examples/aws/backend/dev.hcl`, which every other stack reads:

```hcl
bucket         = "lerian-tfstate-dev-123456789012"
region         = "us-east-1"
dynamodb_table = "lerian-tfstate-lock-dev"
encrypt        = true
```

The file is gitignored because it carries your account id. Keep the local state of the
bootstrap stack as well: its [README](examples/aws/bootstrap/README.md) shows how to keep
it or move it into the new bucket.

## 3. Point each stack at the backend

Every other stack declares an empty `backend "s3" {}`. Its `terraform init` takes two
values: the file from step 2 and a state key. The key is `aws/`, then the stack's path
under `examples/aws/`, then `/terraform.tfstate`. It never names the environment: the
bucket already does.

| Stack directory | Backend file, from the stack | State key |
| --- | --- | --- |
| `examples/aws/infra-base/vpc` | `../../backend/<env>.hcl` | `aws/infra-base/vpc/terraform.tfstate` |
| `examples/aws/infra-base/eks` | `../../backend/<env>.hcl` | `aws/infra-base/eks/terraform.tfstate` |
| `examples/aws/products/<product>/<service>` | `../../../backend/<env>.hcl` | `aws/products/<product>/<service>/terraform.tfstate` |

To point a directory at another environment, run `terraform init -reconfigure` with that
environment's file. Without `-reconfigure`, Terraform offers to copy the state into the
other bucket. Recent Terraform versions also warn that `dynamodb_table` is deprecated in
favour of `use_lockfile`. The warning does not stop `init`.

Each stack ships its variables as `envs/<env>.tfvars-example`. Copy the file to
`envs/<env>.tfvars` and edit it before you plan. `*.tfvars` is gitignored. Use one region
for the whole environment: a product stack must run in the region of the VPC, and the
examples do not all use the same region.

## 4. Deploy the network

```bash
cd examples/aws/infra-base/vpc
terraform init \
  -backend-config=../../backend/dev.hcl \
  -backend-config="key=aws/infra-base/vpc/terraform.tfstate"
cp envs/dev.tfvars-example envs/dev.tfvars   # region and availability_zones must agree
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

This creates the VPC `lerian-dev-vpc`. The other stacks find it by that name, not through
remote state. Keep `product = "lerian"` in both `infra-base` stacks so the names match.

## 5. Deploy the cluster

```bash
cd examples/aws/infra-base/eks
terraform init \
  -backend-config=../../backend/dev.hcl \
  -backend-config="key=aws/infra-base/eks/terraform.tfstate"
cp envs/dev.tfvars-example envs/dev.tfvars
```

In `envs/dev.tfvars`, replace the placeholder in `allowed_api_access_cidrs` with your
public egress address. The plan fails until you do.

```bash
curl -s https://checkip.amazonaws.com        # add /32 to this address
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

This creates the cluster `lerian-dev-eks`. Write it into your kubeconfig:

```bash
$(terraform output -raw update_kubeconfig)
```

The output holds `aws eks update-kubeconfig --name lerian-dev-eks --region <region>`. The
identity that ran the apply is a cluster admin, because every example sets
`enable_cluster_creator_admin_permissions = true`. Anyone else in the account first
assumes the role in the `admin_role_arn` output (cluster admin) or in
`developer_role_arn` (read-only).

## 6. Deploy the product stacks

A product is a directory under `examples/aws/products/`, with one stack per datastore.
Its README lists the stacks and what each one needs.

```bash
cd examples/aws/products/midaz/postgres
terraform init \
  -backend-config=../../../backend/dev.hcl \
  -backend-config="key=aws/products/midaz/postgres/terraform.tfstate"
cp envs/dev.tfvars-example envs/dev.tfvars
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

Repeat in every directory of the product. For midaz that is `postgres`, `documentdb`,
`valkey` and `rabbitmq`, in any order. In each tfvars file, check:

- **`mode`.** `dedicated` creates a datastore for the product. `shared` creates nothing
  and uses the one from `examples/aws/products/shared-resources/<service>`. Apply that
  stack first, the same way.
- **`s3` and `secrets` stacks.** They look up the cluster's OIDC provider, so the
  cluster from step 5 must exist.
- **Stacks with only `envs/prd.tfvars-example`.** Copy it under your environment's name
  and review every value, `environment` and `region` included.

## 7. Hand off to Helm

Every product stack exports `helm_values`: the values it can fill in the product's chart,
under the names the chart reads.

```bash
cd examples/aws/products/midaz/postgres
terraform output -json helm_values
```

The product's README explains where each value goes in the chart. Some stacks return an
empty `helm_values` on purpose, for example when the chart wants a URL that embeds the
password. Wire those from outputs such as `endpoint`, `port` and `secret_name`.

No output carries a password. Datastore stacks export `secret_name` and `secret_arn`,
and the password stays in AWS Secrets Manager.

The charts are at **[LerianStudio/helm](https://github.com/LerianStudio/helm)**.

## 8. Destroy

Destroy in reverse order: the product stacks, then `shared-resources`, then
`infra-base/eks`, then `infra-base/vpc`. In each directory:

```bash
terraform destroy -var-file=envs/dev.tfvars
```

A database applied with `deletion_protection = true`, as in several prd examples, refuses
to be deleted. Set it to `false` and apply before you destroy.

`terraform destroy` on `bootstrap` fails on purpose: `prevent_destroy` guards the lock
table and the bucket that holds the state of every other stack. Its
[README](examples/aws/bootstrap/README.md) describes the teardown.

---

# GCP and Azure

These use the pre-v2 flat layout: one `midaz.tfvars` per component directory, and an
interactive script. Requires `terraform` plus `gcloud` or `az`.

## 1. Create the state bucket

**GCP:**

```bash
gsutil mb -p PROJECT_ID -l REGION gs://BUCKET_NAME
gsutil versioning set on gs://BUCKET_NAME
```

**Azure:**

```bash
az group create --name RESOURCE_GROUP --location LOCATION
az storage account create --name STORAGE_ACCOUNT --resource-group RESOURCE_GROUP \
  --location LOCATION --sku Standard_LRS
az storage container create --name CONTAINER --account-name STORAGE_ACCOUNT
```

## 2. Configure

Each component keeps its own `backend.tf` and `midaz.tfvars`, both edited by hand:

```bash
cd examples/<gcp|azure>/<component>
$EDITOR backend.tf                        # bucket, prefix, credentials
cp midaz.tfvars-example midaz.tfvars
$EDITOR midaz.tfvars
```

The script refuses to deploy a component whose `backend.tf` still holds a
`<PUT-YOUR-...>` placeholder.

## 3. Deploy

```bash
./deploy-legacy.sh
```

Interactive: pick the provider, pick deploy or destroy, pick the components. Order
matters: network first, then the cluster, then the datastores.

| Component | GCP | Azure |
| --- | --- | --- |
| network | `vpc` | `network` |
| dns | `cloud-dns` | `dns` |
| kubernetes | `gke` | `aks` |
| database | `cloud-sql` | `database` |
| valkey | `valkey` | `redis` |
| mongodb | none | `cosmosdb` |

Take the endpoints from `terraform output` and wire them into the charts at
**[LerianStudio/helm](https://github.com/LerianStudio/helm)**.

---

# Important information

Read this before a production deployment.

- **Instance sizing is your responsibility.** The classes in the example `.tfvars` are
  starting points, not a capacity plan. The prd examples step up to multi-AZ and larger
  classes, but only you know your transaction volume, peak concurrency and growth.
  Review instance classes, storage, IOPS and connection limits before applying. Lerian
  is not responsible for performance or cost resulting from those choices.

- **The dev and stg examples create the cluster with a public API endpoint, restricted by
  CIDR.** Set `allowed_api_access_cidrs` to your egress address, as in step 5 of the AWS
  section. For a private endpoint, set `cluster_endpoint_private_access = true` and
  `cluster_endpoint_public_access = false`; the allow-list then has no effect.

- **A VPN and a private cluster are yours to build and operate.** These templates create
  neither. If you go that route: the VPN server needs a Network ACL and a security group
  rule to reach the database subnets on the service port, and a security group rule on
  the control plane to reach the Kubernetes API. Terraform only calls AWS APIs, but
  `kubectl` and `helm` must then run from inside the network.

- **There is no default StorageClass.** The `aws-ebs-csi-driver` add-on installs the
  driver, not a StorageClass, and the `gp2` class EKS ships is not marked default. A PVC
  without an explicit `storageClassName` stays `Pending`. Create a default `gp3` class
  with `volumeBindingMode: WaitForFirstConsumer` before installing anything that needs a
  volume. `Immediate` binds the volume to an AZ before the scheduler picks a node.

- **EBS cannot serve `ReadWriteMany`.** That needs the `aws-efs-csi-driver` add-on,
  which these templates do not install.

- **Cluster add-ons beyond the basics are yours.** `infra-base/eks` installs `coredns`,
  `kube-proxy`, `vpc-cni`, `metrics-server` and `aws-ebs-csi-driver`. Cluster
  Autoscaler, the [AWS Load Balancer
  Controller](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller) and
  an [ingress
  controller](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx) are
  installed by you. The IRSA roles for the first two already exist in
  `examples/aws/infra-base/eks/iam.tf`, and the subnets are already tagged for LB
  discovery. Point the service accounts at the role ARNs rather than creating your own.

- **AmazonMQ speaks AMQPS only.** Any component connecting to it needs the `amqps`
  scheme, for example `RABBITMQ_URI: "amqps"`. Every `rabbitmq` stack exports
  `amqp_endpoint` in that form: `amqps://host:5671`.

- **State is segregated per environment.** dev, stg and prd each get their own bucket
  (`lerian-tfstate-{env}-{account_id}`) and lock table, so a dev apply cannot reach prd
  state even when all three live in the same AWS account.

- **Secrets never leave the cloud.** Passwords and auth tokens are generated by Terraform
  into AWS Secrets Manager and never read back. Outputs carry references, so the whole
  Helm handoff can be printed or logged safely. Saved plan files (`terraform plan -out`)
  are a different matter: they can embed values read from state. `.gitignore` already
  excludes `tfplan*`. Do not archive them.

- **Bringing your own pipeline?** Every step of the AWS section is plain Terraform and
  runs the same from CI. `examples/aws/backend/<env>.hcl` and `envs/*.tfvars` are
  gitignored, so the pipeline must supply them. When the runner cannot write to its
  checkout, set `write_backend_config = false` on `bootstrap` and write the backend file
  yourself, in the shape shown in step 2.

# Reference

## Repository layout

```
deploy-legacy.sh           GCP and Azure, interactive
examples/
  aws/                     v2 layout: environment-scoped, one state per stack
    backend/<env>.hcl      generated by bootstrap
    bootstrap/
    infra-base/{vpc,eks}
    products/<product>/<engine>/
    _modules/              shared datastore modules
  gcp/, azure/             v1 layout: one directory per resource
```

Every root under `examples/aws/` carries a README describing what it creates, what it
costs and how it is configured. Start there for anything this page does not cover.

## Contributing

Install the git hooks before your first commit. They enforce the commit conventions
this repository releases from:

```bash
make hooks
```

Branch from `develop`, commit with [conventional
commits](https://www.conventionalcommits.org/), and open a PR against `develop`. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Report vulnerabilities per [SECURITY.md](SECURITY.md), not through public issues.

## License

Apache 2.0. See [LICENSE](LICENSE).

## Support

Check the README of the root you are deploying, then search
[issues](https://github.com/LerianStudio/lerian-terraform-foundation/issues).
