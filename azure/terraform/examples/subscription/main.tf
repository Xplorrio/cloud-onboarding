# One or more subscriptions, connected today with the customer_principal trust
# mode: an app registration in your tenant gets Reader and Cost Management
# Reader on each subscription. No client secret is created; you add it in the
# portal so it never lands in the Terraform state.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0, < 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9, < 1.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_ids[0]
}

provider "azuread" {}

module "xplorr" {
  source = "../../"

  trust_mode                        = var.trust_mode
  xplorr_application_id             = var.xplorr_application_id
  subscription_ids                  = var.subscription_ids
  display_name                      = var.display_name
  role_names                        = var.role_names
  enable_carbon_optimization_reader = var.enable_carbon_optimization_reader
  enable_reservations_reader        = var.enable_reservations_reader
  enable_savings_plan_reader        = var.enable_savings_plan_reader
  focus_export_scopes               = var.focus_export_scopes
  create_client_secret              = var.create_client_secret

  # Opt-in write access, off by default: a separate custom role for the
  # approved actions you list. The read-only roles are not changed.
  enable_write_role = var.enable_write_role
  write_actions     = var.write_actions
  write_scopes      = var.write_scopes
  # xplorr_principal only: Xplorr's separate write app, shown by Xplorr.
  xplorr_write_application_id = var.xplorr_write_application_id
}
