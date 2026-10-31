# Contributing to lerian-terraform-foundation

This document says how to report a problem and how Lerian engineers change this repository.

## Issues and pull requests

Anyone can open an [issue](https://github.com/LerianStudio/lerian-terraform-foundation/issues) to report a bug or ask for a change. Describe the root you deploy, what happened and what you expected. Report a vulnerability per [SECURITY.md](SECURITY.md), not through a public issue.

Lerian Studio does not accept pull requests from outside contributors. Lerian engineers make every change to this repository.

## Workflow for Lerian engineers

This repository has one branch, `main`. There is no `develop`, and a ruleset blocks creating it.

1. Run `make hooks` once to install the git hooks.
2. Create a branch from `main`: `feat/*` for new features, `fix/*` for bug fixes.
3. Make your changes.
4. Ensure all tests pass and code is properly formatted.
5. Open a pull request against `main`.

## Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types:
- feat: new feature
- fix: bug fix
- docs: documentation changes
- style: formatting changes
- refactor: code restructuring
- test: adding/modifying tests
- chore: maintenance tasks

## Code Standards

1. Use official Terraform modules when available
2. Follow Terraform best practices
3. Include proper documentation
4. Ensure security best practices
5. Write clear and descriptive variable/output names

## Testing

Before submitting a PR:
1. Run `make hooks` to install git hooks
2. Ensure `terraform fmt` passes
3. Ensure `terraform validate` passes
4. Run security checks with `tfsec`

## Documentation

- Update README.md if necessary
- Include module-specific documentation
- Document variables and outputs
- Provide usage examples
