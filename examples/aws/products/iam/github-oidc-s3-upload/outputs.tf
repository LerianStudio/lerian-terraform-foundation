output "role_arns" {
  description = "ARN of each repository's upload role, keyed by owner/repo. Each value goes into the `aws_role_arn` field of the s3_uploads entry in THAT repository's release.yml — the single string that ties that pipeline to its grants here."
  value       = { for repository, role in aws_iam_role.this : repository => role.arn }
}

output "oidc_provider_arn" {
  description = "ARN of this account's GitHub identity provider, the one every role here trusts. AWS refuses a second identity provider for the same URL (EntityAlreadyExists), so a GitHub-OIDC role outside this root must reuse this ARN rather than register its own."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "allowed_subjects" {
  description = "The :sub patterns each role's trust policy admits, keyed by owner/repo, one per listed ref. Echoed back so an apply's evidence names WHAT can assume each role, rather than asserting that roles exist. Read off the SAME local the trust documents are built from, so it cannot report a boundary a role does not have."
  value       = { for repository, upload in local.uploads : repository => upload.trust_subjects }
}

output "object_prefix_arns" {
  description = "The exact object ARNs each role's s3:PutObject is granted over, keyed by owner/repo, one per release channel. Echoed back because the failure this root exists to prevent is a missing channel, which is invisible until a tag of that channel is cut."
  value       = { for repository, upload in local.uploads : repository => upload.object_prefix_arns }
}
