variable "actions" {
  description = <<-EOT
    The Xplorr action types this role may carry out. Only the permissions of the listed types are granted.
    stop_idle_instance: ec2:StopInstances, and ec2:StartInstances to undo it.
    delete_unattached_ebs_volume: ec2:CreateSnapshot first, then ec2:DeleteVolume.
    release_unassociated_eip: ec2:ReleaseAddress.
    rightsize_instance is not listed: Xplorr proposes it as a Terraform pull request, so it needs no permission in your account.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.actions) > 0
    error_message = "List at least one action type. Without one the role would grant nothing."
  }

  validation {
    condition     = alltrue([for a in var.actions : contains(["stop_idle_instance", "delete_unattached_ebs_volume", "release_unassociated_eip"], a)])
    error_message = "actions may hold only stop_idle_instance, delete_unattached_ebs_volume and release_unassociated_eip. rightsize_instance is a Terraform pull request and needs no cloud permission."
  }
}

variable "trust_mode" {
  description = <<-EOT
    Who assumes the role. Use the same mode as your read-only role.
    customer_principal: the IAM user you already use for the read-only role (xplorr-assumer), listed in trusted_principal_arns.
    xplorr_principal: only Xplorr's dedicated actions role (xplorr_principal_arn), with an external ID of its own. Xplorr's sync role cannot assume it.
  EOT
  type        = string
  default     = "customer_principal"

  validation {
    condition     = contains(["customer_principal", "xplorr_principal"], var.trust_mode)
    error_message = "trust_mode must be customer_principal or xplorr_principal."
  }
}

variable "role_name" {
  description = "Name of the write role. Keep the xplorr- prefix: in xplorr_principal mode Xplorr only assumes roles whose name starts with xplorr-."
  type        = string
  default     = "xplorr-write"

  validation {
    condition     = can(regex("^xplorr-[a-z0-9+=,.@_-]{1,57}$", var.role_name))
    error_message = "role_name must start with xplorr- and be at most 64 lowercase characters from a-z, 0-9 and +=,.@_-."
  }
}

variable "trusted_principal_arns" {
  description = "customer_principal only, and required there. The IAM principals allowed to assume the role, normally the user that assumes your read-only role, for example arn:aws:iam::111111111111:user/xplorr-assumer. That user also needs sts:AssumeRole on this role (user_assumable_role_arns in the parent module)."
  type        = list(string)
  default     = []

  validation {
    condition     = var.trust_mode != "customer_principal" || length(var.trusted_principal_arns) > 0
    error_message = "In customer_principal mode list the principal that may assume the role in trusted_principal_arns."
  }
}

variable "xplorr_principal_arn" {
  description = "xplorr_principal only. The one Xplorr role allowed to assume the write role: Xplorr's dedicated actions role, matched exactly (aws:PrincipalArn StringEquals). Xplorr's sync role, which assumes your read-only role, cannot assume this one."
  type        = string
  default     = "arn:aws:iam::732121667940:role/xplorr-actions"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.xplorr_principal_arn)) && !strcontains(var.xplorr_principal_arn, "*")
    error_message = "xplorr_principal_arn must be one exact IAM role ARN such as arn:aws:iam::732121667940:role/xplorr-actions, without wildcards."
  }
}

variable "iam_external_id" {
  description = "The external ID of the write role. It is not the read-only role's external ID: Xplorr shows a separate one for write access. Required for xplorr_principal; optional for customer_principal (generate one with: openssl rand -hex 16)."
  type        = string
  default     = ""

  validation {
    condition     = var.trust_mode != "xplorr_principal" || length(var.iam_external_id) >= 2
    error_message = "iam_external_id is required when trust_mode is xplorr_principal. Use the write access external ID Xplorr shows you."
  }

  validation {
    condition     = var.iam_external_id == "" || (length(var.iam_external_id) >= 2 && length(var.iam_external_id) <= 1224 && can(regex("^[A-Za-z0-9+=,.@:/_-]+$", var.iam_external_id)))
    error_message = "iam_external_id must be 2 to 1224 characters from A-Z, a-z, 0-9 and +=,.@:/_-."
  }
}

variable "protect_tag_key" {
  description = "Resources carrying this tag with the value true (any case) are refused by an explicit Deny, whatever Xplorr asks for. Set it to an empty string to turn the guard off."
  type        = string
  default     = "xplorr:protect"

  validation {
    condition     = var.protect_tag_key == "" || can(regex("^[A-Za-z0-9 +=._:/@-]{1,128}$", var.protect_tag_key))
    error_message = "protect_tag_key must be a valid AWS tag key (up to 128 characters from letters, digits, spaces and +=._:/@-), or empty."
  }
}

variable "allowed_regions" {
  description = "Optional. Regions the role may act in (aws:RequestedRegion), for example [\"us-east-1\", \"eu-west-1\"]. Empty means every region."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "Each allowed_regions entry must be an AWS region such as us-east-1."
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
  description = "Optional permissions boundary for the role."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags added to the role."
  type        = map(string)
  default     = {}
}
