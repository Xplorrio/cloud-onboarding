variable "subscription_ids" {
  description = "Subscriptions to connect to Xplorr. The first one is also the azurerm provider's subscription."
  type        = list(string)
}

variable "trust_mode" {
  description = "customer_principal (default, works today) or xplorr_principal (coming soon)."
  type        = string
  default     = "customer_principal"
}

variable "xplorr_application_id" {
  description = "xplorr_principal only. Xplorr's multi-tenant application (client) ID, from Xplorr."
  type        = string
  default     = ""
}

variable "display_name" {
  description = "Display name of the app registration."
  type        = string
  default     = "xplorr-reader"
}

variable "role_names" {
  description = "Read-only roles on each subscription."
  type        = list(string)
  default     = ["Reader", "Cost Management Reader"]
}

variable "enable_carbon_optimization_reader" {
  description = "Also assign Carbon Optimization Reader, for carbon emissions."
  type        = bool
  default     = false
}

variable "enable_reservations_reader" {
  description = "Assign Reservations Reader at tenant scope. Needs elevated access."
  type        = bool
  default     = false
}

variable "enable_savings_plan_reader" {
  description = "Assign Savings plan reader at tenant scope. Needs elevated access."
  type        = bool
  default     = false
}

variable "focus_export_scopes" {
  description = "Storage account or container resource IDs holding a FOCUS export."
  type        = list(string)
  default     = []
}

variable "create_client_secret" {
  description = "Create the client secret with Terraform. It is then stored in the state."
  type        = bool
  default     = false
}

variable "enable_write_role" {
  description = "Opt in to write access: create the xplorr-write custom role for the action types in write_actions. Off by default."
  type        = bool
  default     = false
}

variable "write_actions" {
  description = "Action types the custom role may carry out: deallocate_idle_vm."
  type        = list(string)
  default     = []
}

variable "write_scopes" {
  description = "Optional resource group IDs to assign the custom role on. Empty assigns it where the read-only roles are."
  type        = list(string)
  default     = []
}
