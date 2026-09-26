variable "region" {
  description = "Region for the providers and the Region field in Xplorr."
  type        = string
  default     = "us-east-1"
}

variable "role_name" {
  description = "Name of the read-only role, the same in every account."
  type        = string
  default     = "xplorr-readonly"
}

variable "iam_external_id" {
  description = "Optional external ID, the same in every account. Generate one with: openssl rand -hex 16. Enter it in Xplorr for each account."
  type        = string
  default     = ""
}

variable "member_access_role_name" {
  description = "Role Terraform assumes to reach each member account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "member_a_account_id" {
  description = "First member account ID."
  type        = string
}

variable "member_b_account_id" {
  description = "Second member account ID."
  type        = string
}
