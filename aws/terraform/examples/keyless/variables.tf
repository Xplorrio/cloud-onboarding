variable "xplorr_account_id" {
  description = "The Xplorr AWS account the role trusts."
  type        = string
  default     = "732121667940"
}

variable "iam_external_id" {
  description = "The external ID Xplorr generates for your organization and shows on the Connect account form."
  type        = string
}
