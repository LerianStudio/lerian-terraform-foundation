# Variables for the Lerian agent install.
#
# The first four are the repository's standard set; everything after them is the
# agent chart's contract, narrowed to what a cluster install actually decides.

variable "region" {
  description = "AWS region the cluster is in."
  type        = string
}

variable "environment" {
  description = "Environment identifier."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster to install the agent into - the `name` the eks root was given."
  type        = string
}

variable "chart_version" {
  description = "Version of the agent-helm chart. Empty takes the newest published version; set it to pin, which is what a production cluster should do."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace the agent runs in."
  type        = string
  default     = "lerian-system"
}

variable "control_plane_url" {
  description = "Base URL of the Lerian control plane. Must be https:// unless allow_insecure_http is true."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.control_plane_url))
    error_message = "control_plane_url must start with http:// or https://."
  }
}

variable "allow_insecure_http" {
  description = "Accept a cleartext http:// control_plane_url. Isolated dev clusters only: the agent sends its bearer token on every request."
  type        = bool
  default     = false
}

variable "agent_token" {
  description = "Per-agent token from POST /api/tenants/:id/agents, or a single-use enrollment token (lerian_enroll_...). Leave empty when using existing_secret_name."
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_id" {
  description = "Agent UUID that came with a per-agent token. Leave empty for an enrollment token: the agent is told its identity when it redeems one."
  type        = string
  default     = ""
}

variable "existing_secret_name" {
  description = "Name of a Secret already in the cluster holding AGENT_TOKEN (and AGENT_ID for a per-agent token). Set this instead of agent_token to keep the credential out of Terraform state."
  type        = string
  default     = ""
}

variable "managed_namespaces" {
  description = "Namespaces the agent may install stacks into. Each must already exist. Empty means the agent's own namespace only."
  type        = list(string)
  default     = []
}

variable "image_repository" {
  description = "Agent image. Empty takes the chart's default (ghcr.io/lerianstudio/agent). Set docker.io/lerianstudio/agent to pull from Docker Hub instead."
  type        = string
  default     = ""
}

variable "allowed_image_registries" {
  description = "Registries the agent may pull its OWN image from, comma separated. Empty takes the chart's default (ghcr.io/lerianstudio). Must include the host of image_repository or the agent refuses its own self-update."
  type        = string
  default     = ""
}

variable "image_digest" {
  description = "Image digest (sha256:...), which wins over the tag. Set this after the control plane has moved the agent to a newer build, so the next apply does not put the old tag back."
  type        = string
  default     = ""
}

variable "image_pull_secrets" {
  description = "Names of imagePullSecrets for the agent image. Both published images are public today, so this is normally empty."
  type        = list(string)
  default     = []
}

variable "timeout_seconds" {
  description = "How long helm waits for the agent to become ready."
  type        = number
  default     = 600
}
