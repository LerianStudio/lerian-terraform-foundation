# Midaz Terraform Foundation Changelog

## [1.4.0](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.4.0)

- **Features:**
  - Updated AWS instance types to newer generation (m7g) and added disclaimer for instance type selection.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.3.0...v1.4.0)

---

## [1.3.0](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.3.0)

- **Features:**
  - Added AWS Load Balancer Controller support for EKS clusters.
  - Improved EKS configuration with additional security and networking options.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.2.0...v1.3.0)

---

## [1.2.0](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.2.0)

- **Features:**
  - Added DocumentDB infrastructure module for MongoDB-compatible database deployments.
  - Updated EKS tfvars and addons configuration.

- **Improvements:**
  - Updated AWS EKS Terraform module to v21.0 with renamed parameters.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.1.0...v1.2.0)

---

## [1.1.0](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.1.0)

- **Features:**
  - Created AmazonMQ module for RabbitMQ broker deployments.
  - Created DocumentDB module for MongoDB-compatible deployments.
  - Added optional TLS parameter for RDS and Valkey modules.
  - Added KMS key encryption for DocumentDB.
  - Added storage encryption for DocumentDB.
  - Added components for different cloud providers (AWS, GCP, Azure).
  - Added CosmosDB module for Azure resources.

- **Fixes:**
  - Excluded audit logging for RabbitMQ vulnerability in tfsec.
  - Removed unusable parameters from modules.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.0.2...v1.1.0)

---

## [1.0.2](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.0.2)

- **Fixes:**
  - Fixed small issues on AWS template configurations.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.0.1...v1.0.2)

---

## [1.0.1](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.0.1)

- **Fixes:**
  - Updated deploy script and infrastructure configurations.

- **Improvements:**
  - Updated GKE setup for ARM compatibility.

[Compare changes](https://github.com/LerianStudio/midaz-terraform-foundation/compare/v1.0.0...v1.0.1)

---

## [1.0.0](https://github.com/LerianStudio/midaz-terraform-foundation/releases/tag/v1.0.0)

- **Features:**
  - Initial release of Midaz Terraform Foundation.
  - AWS infrastructure modules: VPC, Route53, RDS, Valkey, EKS, AmazonMQ.
  - GCP infrastructure modules: VPC, Cloud DNS, Cloud SQL, Valkey, GKE.
  - Azure infrastructure modules: Network, DNS, Database, Redis, AKS.
  - Multi-cloud deployment script with interactive prompts.
  - Semantic versioning with automated releases.

- **Improvements:**
  - Enhanced security configurations across all cloud providers.
  - Standardized naming conventions for infrastructure components.

[View all changes](https://github.com/LerianStudio/midaz-terraform-foundation/commits/v1.0.0)
