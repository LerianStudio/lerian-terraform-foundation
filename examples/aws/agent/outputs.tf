output "release_name" {
  description = "Helm release name. The resources inside it are named lerian-agent regardless of this."
  value       = helm_release.agent.name
}

output "namespace" {
  description = "Namespace the agent runs in."
  value       = helm_release.agent.namespace
}

output "chart_version" {
  description = "Version of agent-helm that is installed."
  value       = helm_release.agent.version
}

output "cluster_name" {
  description = "Cluster the agent was installed into."
  value       = var.cluster_name
}

output "managed_namespaces" {
  description = "Namespaces the agent may install into. Each has to exist already; adding one needs another apply."
  value       = var.managed_namespaces
}

output "identity_secret" {
  description = "Secret the agent keeps its identity in after redeeming an enrollment token. Kept on uninstall, so a reinstall reuses the same identity."
  value       = "lerian-agent-identity"
}
