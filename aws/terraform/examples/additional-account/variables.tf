variable "region" {
  description = "Region for the AWS provider and the Region field in Xplorr."
  type        = string
  default     = "us-east-1"
}

variable "trusted_user_arn" {
  description = "ARN of the Xplorr user in your first account (output user_arn of examples/basic)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:user/.+$", var.trusted_user_arn))
    error_message = "trusted_user_arn must be an IAM user ARN such as arn:aws:iam::111111111111:user/xplorr-assumer."
  }
}

variable "role_name" {
  description = "Name of the read-only role. Use the same name as in your first account."
  type        = string
  default     = "xplorr-readonly"
}

variable "iam_external_id" {
  description = "Optional external ID for this account's role. Enter the same value in Xplorr for this account."
  type        = string
  default     = ""
}
