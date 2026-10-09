# The Lerian agent: the process inside this cluster that polls the control plane
# and runs the Helm operations it is given.
#
# It is installed here, by Terraform, rather than by a person running `helm
# install` once. The difference is what happens afterwards: a release in state
# is reconciled on every apply, so the version, the managed namespaces and the
# control plane URL are whatever this code says they are — and removing the
# target removes the agent, instead of leaving one behind that nobody remembers
# installing.
#
# What this root does NOT do is provision anything in AWS. The cluster, its
# network and the datastores belong to the other infra-base roots and to the
# product roots; this one only puts a workload in a cluster that already exists.

locals {
  # The cluster the eks root created. Named rather than derived, because the
  # name there is a variable with no shape this root can reproduce.
  cluster_name = var.cluster_name

  # Either a token this root writes into a Secret the chart creates, or a Secret
  # somebody else put in the cluster. The chart refuses both being absent, and
  # it is worth refusing here instead: the message arrives at plan time, naming
  # the variable, rather than at apply time naming a template line.
  use_existing_secret = var.existing_secret_name != ""

  # What the agent will actually enforce, which is not always what this root
  # sets. Leaving allowed_image_registries empty does not mean "any registry":
  # it means the chart keeps its own default, and the agent then refuses a
  # self-update from anywhere else. The precondition below has to compare
  # against this rather than against the variable, or pointing image_repository
  # at Docker Hub and leaving the allowlist alone passes the check and breaks
  # the first self-update.
  effective_registries = var.allowed_image_registries != "" ? var.allowed_image_registries : local.chart_default_registries

  # The chart's default for AGENT_ALLOWED_IMAGE_REGISTRIES. Written down because
  # a default that is only in somebody else's values.yaml cannot be reasoned
  # about here.
  chart_default_registries = "ghcr.io/lerianstudio"

  # The registry part of image_repository: "docker.io/lerianstudio/agent" is
  # registered at "docker.io/lerianstudio". A repository with fewer than three
  # segments has no registry to extract, and is left to the check below to pass
  # rather than crashing the plan on a slice that runs off the end.
  image_repository_parts = split("/", var.image_repository)
  image_registry         = length(local.image_repository_parts) >= 3 ? join("/", slice(local.image_repository_parts, 0, 2)) : ""

  # Values the chart reads. Written as one YAML document rather than as a list
  # of `set` blocks: `set` puts every value in the plan output, and one of these
  # is a credential.
  values = yamlencode({
    agent = merge(
      {
        configmap = merge(
          {
            CONTROL_PLANE_URL         = var.control_plane_url
            AGENT_ALLOW_INSECURE_HTTP = var.allow_insecure_http ? "true" : "false"
          },
          var.allowed_image_registries != "" ? {
            AGENT_ALLOWED_IMAGE_REGISTRIES = var.allowed_image_registries
          } : {}
        )

        managedNamespaces = var.managed_namespaces
        imagePullSecrets  = [for name in var.image_pull_secrets : { name = name }]
      },

      # One or the other, never both: the chart treats useExistingSecret as the
      # switch, and sending a token alongside it writes a Secret nothing reads.
      #
      # Two merges rather than one conditional, because the branches carry
      # different keys and Terraform unifies the types of both arms.
      local.use_existing_secret ? {
        useExistingSecret  = true
        existingSecretName = var.existing_secret_name
      } : {},

      local.use_existing_secret ? {} : {
        secrets = {
          AGENT_TOKEN = var.agent_token
          AGENT_ID    = var.agent_id
        }
      },

      # Left out entirely when empty, so the chart's own defaults apply. An
      # explicit "" would override them with nothing.
      var.image_repository != "" || var.image_digest != "" ? {
        image = merge(
          var.image_repository != "" ? { repository = var.image_repository } : {},
          var.image_digest != "" ? { digest = var.image_digest } : {},
        )
      } : {},
    )
  })
}

# The chart refuses a per-agent token without its id, and refuses both forms
# being absent. Caught here so the failure names the variable to set rather than
# a line in a template.
resource "terraform_data" "credential_check" {
  lifecycle {
    precondition {
      condition     = local.use_existing_secret || var.agent_token != ""
      error_message = "Set agent_token, or existing_secret_name for a Secret already in the cluster. The agent cannot authenticate without one of them."
    }

    precondition {
      condition     = !startswith(var.agent_token, "lerian_enroll_") || var.agent_id == ""
      error_message = "agent_id must be empty with an enrollment token: the agent is given its identity when it redeems one."
    }

    precondition {
      condition     = var.allow_insecure_http || startswith(var.control_plane_url, "https://")
      error_message = "control_plane_url must be https://. The agent sends its bearer token on every request; set allow_insecure_http only for an isolated dev cluster."
    }

    # The agent checks this itself and refuses a self-update from a registry it
    # does not allow — but it checks at update time, which is weeks later and in
    # somebody else's terminal.
    precondition {
      condition = local.image_registry == "" ? true : contains(
        [for r in split(",", local.effective_registries) : trimspace(r)],
        local.image_registry
      )
      error_message = "The agent's allowed registries must contain the registry of image_repository, or it will refuse its own self-update. Leaving allowed_image_registries empty keeps the chart's default of ghcr.io/lerianstudio — set it alongside image_repository."
    }
  }
}

resource "helm_release" "agent" {
  name       = "lerian-agent"
  repository = "oci://ghcr.io/lerianstudio"
  chart      = "agent-helm"
  version    = var.chart_version

  namespace        = var.namespace
  create_namespace = true

  values = [local.values]

  # Waits for the Deployment to be ready, so a failed install is a failed apply
  # rather than a green one followed by a pod nobody looks at.
  wait    = true
  timeout = var.timeout_seconds

  # Left in place when the pod does not come up, so `kubectl logs` and `describe`
  # still have something to read. A rolled-back release deletes the evidence.
  atomic = false

  depends_on = [terraform_data.credential_check]
}
