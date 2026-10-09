terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned to the 3.x line like every other Azure root here. Without a
      # ceiling this one resolved a 5.x provider, where
      # azurerm_private_dns_a_record replaced zone_name and resource_group_name
      # with private_dns_zone_id — so the root stopped validating against code
      # that had not changed.
      version = "~> 3.0"
    }
  }
}
