variable "trust_mode" {
  description = <<-EOT
    Who assumes the role.
    customer_principal (default, works today): an IAM user assumes the role. You create an access key for that user in the console and save it in Xplorr once, as your organization's base keys.
    xplorr_principal (requires Xplorr keyless onboarding, coming soon): the role trusts Xplorr's AWS account directly, limited to Xplorr roles named xplorr-*, with an external ID. No user and no keys.
  EOT
  type        = string
  default     = "customer_principal"

  validation {
    condition     = contains(["customer_principal", "xplorr_principal"], var.trust_mode)
    error_message = "trust_mode must be customer_principal or xplorr_principal."
  }
}

variable "role_name" {
  description = "Name of the read-only role Xplorr assumes. Enter the same value in the Role name field of the Xplorr Connect account form."
  type        = string
  default     = "xplorr-readonly"

  validation {
    # The clouddrove labels module lowercases names, so an uppercase name would
    # be created under a different spelling than the one you type in Xplorr.
    condition     = can(regex("^[a-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1 to 64 lowercase characters from a-z, 0-9 and +=,.@_-."
  }
}

variable "create_user" {
  description = "customer_principal only. Create the IAM user that assumes the role. Xplorr keeps one set of base keys per organization, so create the user in one account only (your first or management account) and set this to false everywhere else, trusting that user through trusted_principal_arns."
  type        = bool
  default     = true
}

variable "user_name" {
  description = "customer_principal only. Name of the IAM user that assumes the role. Terraform creates no access key for it."
  type        = string
  default     = "xplorr-assumer"

  validation {
    condition     = can(regex("^[a-z0-9+=,.@_-]{1,64}$", var.user_name))
    error_message = "user_name must be 1 to 64 lowercase characters from a-z, 0-9 and +=,.@_-."
  }
}

variable "trusted_principal_arns" {
  description = "customer_principal only. Further IAM principals allowed to assume the role. In every account except the one holding the user, this is the ARN of that user, for example arn:aws:iam::111111111111:user/xplorr-assumer."
  type        = list(string)
  default     = []

  validation {
    condition     = var.trust_mode != "customer_principal" || var.create_user || length(var.trusted_principal_arns) > 0
    error_message = "In customer_principal mode the role needs someone to trust: keep create_user = true or list trusted_principal_arns."
  }
}

variable "user_assumable_role_arns" {
  description = "customer_principal only, where the user is created. Roles in other accounts the user may assume, for example arn:aws:iam::222222222222:role/xplorr-readonly. Each of those roles must also trust the user."
  type        = list(string)
  default     = []
}

variable "user_assumable_org_id" {
  description = "customer_principal only, where the user is created. An AWS Organizations id (o-...). When set, the user may assume a role named role_name in any account of that organization, which suits a StackSet that adds accounts later. Each role must still trust the user."
  type        = string
  default     = ""

  validation {
    condition     = var.user_assumable_org_id == "" || can(regex("^o-[a-z0-9]{10,32}$", var.user_assumable_org_id))
    error_message = "user_assumable_org_id must be an organization id such as o-abcd123456, or empty."
  }
}

variable "xplorr_account_id" {
  description = "xplorr_principal only. The Xplorr AWS account the role trusts."
  type        = string
  default     = "732121667940"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.xplorr_account_id))
    error_message = "xplorr_account_id must be a 12 digit AWS account id."
  }
}

variable "xplorr_principal_role_pattern" {
  description = "xplorr_principal only. Only roles in the Xplorr account whose name matches this pattern may assume the role (aws:PrincipalArn condition)."
  type        = string
  default     = "xplorr-*"
}

variable "iam_external_id" {
  description = "External ID required in the trust policy (the External ID field in Xplorr). Required for xplorr_principal, where Xplorr will generate it for your organization. Optional for customer_principal; generate one with: openssl rand -hex 16"
  type        = string
  default     = ""

  validation {
    condition     = var.trust_mode != "xplorr_principal" || length(var.iam_external_id) >= 2
    error_message = "iam_external_id is required when trust_mode is xplorr_principal. Use the value Xplorr shows you."
  }

  validation {
    condition     = var.iam_external_id == "" || (length(var.iam_external_id) >= 2 && length(var.iam_external_id) <= 1224 && can(regex("^[A-Za-z0-9+=,.@:/_-]+$", var.iam_external_id)))
    error_message = "iam_external_id must be 2 to 1224 characters from A-Z, a-z, 0-9 and +=,.@:/_-."
  }
}

variable "region" {
  description = "Region Xplorr uses for STS and CloudTrail calls. Enter the same value in the Region field in Xplorr. Cost Explorer is always read from us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "attach_readonly_access" {
  description = "Also attach the AWS managed ReadOnlyAccess policy. Off by default and not needed: the least-privilege policy covers every call Xplorr makes. ReadOnlyAccess is much wider: it can read data, not just metadata, including S3 objects, DynamoDB items, SQS messages and many other services' contents. Only turn it on if your policy prefers AWS managed policies."
  type        = bool
  default     = false
}

variable "enable_audit_log" {
  description = "Grant cloudtrail:LookupEvents. Xplorr calls it on each sync to record whether audit log access works, and will use it for anomaly root cause analysis."
  type        = bool
  default     = true
}

variable "export_bucket_arns" {
  description = "Optional. ARNs of S3 buckets that hold a FOCUS billing export or the carbon footprint export, for example arn:aws:s3:::example-focus-exports. Grants s3:ListBucket and s3:GetObject on them."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.export_bucket_arns : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9.-]{3,63}$", arn))])
    error_message = "Each export_bucket_arns entry must be a bucket ARN such as arn:aws:s3:::example-focus-exports, without a key path."
  }
}

variable "export_kms_key_arns" {
  description = "Optional. ARNs of the KMS keys that encrypt the export buckets (SSE-KMS), for example arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000. Grants kms:Decrypt on them so s3:GetObject can read the objects. Not needed for SSE-S3 (the default bucket encryption)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.export_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", arn))])
    error_message = "Each export_kms_key_arns entry must be a KMS key ARN such as arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000."
  }
}

variable "max_session_duration" {
  description = "Maximum session length for the role, in seconds. Xplorr requests one hour sessions, so this must be at least 3600."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary for the role and the user."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags added to the role. The clouddrove iam-user module 1.3.2 does not apply custom tags to the user; it tags it with Name, Managedby and Repository."
  type        = map(string)
  default     = {}
}

# Opt-in write access. Off by default. The write role is a separate role
# (modules/write-role) with its own external ID; the read-only role above
# never gains a write permission.

variable "enable_write_role" {
  description = "Create the separate xplorr-write role, so Xplorr can carry out the approved actions listed in write_actions. Off by default. The read-only role is not changed."
  type        = bool
  default     = false
}

variable "write_actions" {
  description = "With enable_write_role. The action types the write role may carry out: stop_idle_instance, delete_unattached_ebs_volume, release_unassociated_eip. Only their permissions are granted. rightsize_instance needs no cloud permission (it is a Terraform pull request)."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_write_role || length(var.write_actions) > 0
    error_message = "enable_write_role = true needs at least one action type in write_actions."
  }

  validation {
    condition     = alltrue([for a in var.write_actions : contains(["stop_idle_instance", "delete_unattached_ebs_volume", "release_unassociated_eip"], a)])
    error_message = "write_actions may hold only stop_idle_instance, delete_unattached_ebs_volume and release_unassociated_eip. rightsize_instance is a Terraform pull request and needs no cloud permission."
  }
}

variable "write_role_name" {
  description = "With enable_write_role. Name of the write role. Keep the xplorr- prefix: in xplorr_principal mode Xplorr only assumes roles whose name starts with xplorr-."
  type        = string
  default     = "xplorr-write"

  validation {
    condition     = can(regex("^xplorr-[a-z0-9+=,.@_-]{1,57}$", var.write_role_name))
    error_message = "write_role_name must start with xplorr- and be at most 64 lowercase characters from a-z, 0-9 and +=,.@_-."
  }

  validation {
    condition     = var.write_role_name != var.role_name
    error_message = "write_role_name must differ from role_name: the write role is a separate role."
  }
}

variable "write_iam_external_id" {
  description = "With enable_write_role. The write role's external ID, which is not the read-only role's: Xplorr shows a separate one for write access. Required for xplorr_principal; optional for customer_principal (generate one with: openssl rand -hex 16)."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_write_role || var.trust_mode != "xplorr_principal" || length(var.write_iam_external_id) >= 2
    error_message = "write_iam_external_id is required for the write role when trust_mode is xplorr_principal. Use the write access external ID Xplorr shows you."
  }

  validation {
    condition     = var.write_iam_external_id == "" || var.write_iam_external_id != var.iam_external_id
    error_message = "write_iam_external_id must differ from iam_external_id, so the read-only role's external ID cannot assume the write role."
  }
}

variable "write_xplorr_principal_arn" {
  description = "With enable_write_role, xplorr_principal only. The one Xplorr role allowed to assume the write role, matched exactly: Xplorr's dedicated actions role. The read-only role keeps trusting Xplorr roles named xplorr-*."
  type        = string
  default     = "arn:aws:iam::732121667940:role/xplorr-actions"
}

variable "write_protect_tag_key" {
  description = "With enable_write_role. Resources tagged with this key and the value true (any case) are refused by an explicit Deny. An empty string turns the guard off."
  type        = string
  default     = "xplorr:protect"
}

variable "write_allowed_regions" {
  description = "With enable_write_role. Optional. Regions the write role may act in (aws:RequestedRegion). Empty means every region."
  type        = list(string)
  default     = []
}
