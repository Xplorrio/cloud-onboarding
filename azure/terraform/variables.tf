variable "trust_mode" {
  description = <<-EOT
    Which identity Xplorr signs in as.
    customer_principal (default, works today): an app registration and service principal in your tenant. You create its client secret and give it to Xplorr.
    xplorr_principal (coming soon, needs Xplorr keyless onboarding): the service principal of Xplorr's multi-tenant app, identified by xplorr_application_id. No secret of yours is stored anywhere.
  EOT
  type        = string
  default     = "customer_principal"

  validation {
    condition     = contains(["customer_principal", "xplorr_principal"], var.trust_mode)
    error_message = "trust_mode must be customer_principal or xplorr_principal."
  }
}

variable "subscription_ids" {
  description = "Subscriptions to connect. One Xplorr cloud account is one subscription, so each one gets its own entry in the xplorr_connect_form output. Roles are assigned on each, unless management_group_id is set."
  type        = list(string)

  validation {
    condition     = length(var.subscription_ids) > 0 && alltrue([for s in var.subscription_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", s))])
    error_message = "subscription_ids must list at least one subscription ID (a GUID)."
  }
}

variable "management_group_id" {
  description = "Optional. The name (ID) of a management group, for example mg-example. The roles are then assigned once on it instead of on each subscription, and every subscription below it inherits them. List the subscriptions you want in Xplorr in subscription_ids all the same."
  type        = string
  default     = ""
}

variable "role_names" {
  description = "Read-only built-in roles assigned on each subscription (or the management group). Reader covers every subscription call Xplorr makes, including the Activity Log. Cost Management Reader is kept alongside it because many policies require it. Monitoring Reader is the alternative to Reader for the Activity Log when Reader is not allowed."
  type        = list(string)
  default     = ["Reader", "Cost Management Reader"]

  validation {
    condition     = length(var.role_names) > 0 && alltrue([for r in var.role_names : contains(["Reader", "Cost Management Reader", "Monitoring Reader"], r)])
    error_message = "role_names may hold only Reader, Cost Management Reader and Monitoring Reader."
  }

  validation {
    condition     = contains(var.role_names, "Reader") || contains(var.role_names, "Monitoring Reader")
    error_message = "Include Reader, or Monitoring Reader alongside Cost Management Reader: Cost Management Reader alone cannot read the Activity Log or the resource inventory."
  }
}

variable "enable_carbon_optimization_reader" {
  description = "Also assign Carbon Optimization Reader on the same scopes, for Xplorr's carbon emissions reports."
  type        = bool
  default     = false
}

variable "enable_reservations_reader" {
  description = "Assign Reservations Reader at tenant scope (/providers/Microsoft.Capacity), for Xplorr's commitments view. Whoever runs Terraform needs User Access Administrator at that scope, which usually means elevated access for a Global Administrator."
  type        = bool
  default     = false
}

variable "enable_savings_plan_reader" {
  description = "Assign Savings plan reader at tenant scope (/providers/Microsoft.BillingBenefits), for Xplorr's commitments view. Off by default: the role is named on Microsoft's savings plan permissions page but not on the built-in roles page, so its id could not be verified and it is looked up by name at that scope. If the lookup fails, assign it with az (see the README). Same rights needed as enable_reservations_reader."
  type        = bool
  default     = false
}

variable "focus_export_scopes" {
  description = "Optional. Resource IDs of the storage accounts (or containers) that hold a FOCUS cost export Xplorr should read. Storage Blob Data Reader is assigned on each."
  type        = list(string)
  default     = []
}

variable "display_name" {
  description = "customer_principal only. Display name of the app registration."
  type        = string
  default     = "xplorr-reader"
}

variable "owner_object_id" {
  description = "customer_principal only. Object ID of the app registration's owner (a user or service principal). Defaults to the identity running Terraform."
  type        = string
  default     = ""
}

variable "create_client_secret" {
  description = "customer_principal only. Create the client secret with Terraform. WARNING: the secret value is then stored in plain text in the Terraform state. Leave this false and create the secret in the portal instead."
  type        = bool
  default     = false
}

variable "client_secret_duration" {
  description = "customer_principal only, with create_client_secret. How long the secret stays valid, as a Terraform duration, for example 17520h for two years. The module counts it from its 180 day rotation timestamp."
  type        = string
  default     = "17520h"

  validation {
    condition     = can(regex("^[0-9]+h$", var.client_secret_duration))
    error_message = "client_secret_duration must be a number of hours, for example 17520h."
  }
}

variable "xplorr_application_id" {
  description = "xplorr_principal only, and required there. The application (client) ID of Xplorr's multi-tenant app, which Xplorr shows you when keyless onboarding is available. There is no default on purpose."
  type        = string
  default     = ""

  validation {
    condition     = var.trust_mode != "xplorr_principal" || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.xplorr_application_id))
    error_message = "xplorr_application_id (a GUID) is required when trust_mode is xplorr_principal."
  }
}
