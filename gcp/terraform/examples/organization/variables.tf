variable "project_id" {
  description = "The project that holds the Cloud Billing export dataset. The service account is created here."
  type        = string
}

variable "billing_dataset_id" {
  description = "The billing export dataset."
  type        = string
  default     = "billing_export"
}

variable "bigquery_location" {
  description = "Location of the dataset: US, EU or a region."
  type        = string
  default     = "US"
}

variable "billing_account_id" {
  description = "Billing account id, for spend based CUD recommendations and budget hints."
  type        = string
  default     = null
}

variable "enable_org_level_grants" {
  description = "Also grant the read roles on organization_id or folder_ids. Off by default: Xplorr currently reads only the connected project, so these grants give it nothing today."
  type        = bool
  default     = false
}

variable "organization_id" {
  description = "Numeric organization id, used only with enable_org_level_grants = true."
  type        = string
  default     = null
}

variable "folder_ids" {
  description = "Numeric folder ids, used only with enable_org_level_grants = true."
  type        = list(string)
  default     = []
}
