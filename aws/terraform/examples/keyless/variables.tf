variable "xplorr_account_id" {
  description = "The Xplorr AWS account the role trusts."
  type        = string
  default     = "732121667940"
}

variable "iam_external_id" {
  description = "The external ID Xplorr generates for your organization and shows on the Connect account form."
  type        = string
}

variable "enable_write_role" {
  description = "Opt in to write access: create the separate xplorr-write role for the action types in write_actions. Off by default."
  type        = bool
  default     = false
}

variable "write_actions" {
  description = "Action types the write role may carry out: stop_idle_instance, delete_unattached_ebs_volume, release_unassociated_eip."
  type        = list(string)
  default     = []
}

variable "write_iam_external_id" {
  description = "The write access external ID Xplorr shows you, different from iam_external_id. Required with enable_write_role."
  type        = string
  default     = ""
}
