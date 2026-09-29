variable "project_id" {
  description = "The project that holds (or will hold) the Cloud Billing export dataset."
  type        = string
}

variable "billing_dataset_id" {
  description = "The billing export dataset."
  type        = string
  default     = "billing_export"
}

variable "create_billing_dataset" {
  description = "Create the dataset. Leave false if the export is already on."
  type        = bool
  default     = false
}

variable "bigquery_location" {
  description = "Location of the dataset: US, EU or a region."
  type        = string
  default     = "US"
}

variable "billing_table" {
  description = "The standard export table name, or null for the wildcard."
  type        = string
  default     = null
}

variable "billing_account_id" {
  description = "Optional billing account id, for spend based CUD recommendations and budget hints."
  type        = string
  default     = null
}

variable "enable_write_role" {
  description = "Opt in to write access: create the xplorrWrite custom role for the action types in write_actions. Off by default."
  type        = bool
  default     = false
}

variable "write_actions" {
  description = "Action types the custom role may carry out: stop_idle_instance."
  type        = list(string)
  default     = []
}

variable "write_protect_tag" {
  description = "Optional namespaced tag key, for example my-project-id/xplorr-protect. Instances tagged with it and the value true are refused."
  type        = string
  default     = null
}
