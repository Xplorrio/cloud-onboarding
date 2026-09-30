variable "region" {
  description = "Region for the AWS provider and the Region field in Xplorr."
  type        = string
  default     = "us-east-1"
}

variable "role_name" {
  description = "Name of the read-only role."
  type        = string
  default     = "xplorr-readonly"
}

variable "iam_external_id" {
  description = "Optional external ID. Generate one with: openssl rand -hex 16. Enter the same value in Xplorr."
  type        = string
  default     = ""
}

variable "attach_readonly_access" {
  description = "Also attach the AWS managed ReadOnlyAccess policy. Not needed, and much wider than the least-privilege policy."
  type        = bool
  default     = false
}

variable "user_assumable_role_arns" {
  description = "Roles created in other standalone accounts with examples/additional-account, which the user in this account may assume."
  type        = list(string)
  default     = []
}
