variable "project_id" {
  description = "The project you connect to Xplorr. It holds the Cloud Billing export dataset, the service account is created in it, and Xplorr's BigQuery jobs run (and are billed) in it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a Google Cloud project id, for example my-project-id."
  }
}

variable "trust_mode" {
  description = <<-EOT
    How Xplorr signs in.
    customer_principal (default, works today): a service account in your project. You create its key yourself with gcloud and paste it into Xplorr.
    xplorr_principal (coming soon, not live yet): the same service account with no key; Xplorr's own service account impersonates it through roles/iam.serviceAccountTokenCreator.
  EOT
  type        = string
  default     = "customer_principal"

  validation {
    condition     = contains(["customer_principal", "xplorr_principal"], var.trust_mode)
    error_message = "trust_mode must be customer_principal or xplorr_principal."
  }
}

variable "xplorr_service_account_email" {
  description = "Only for trust_mode = xplorr_principal: the Xplorr service account that may impersonate yours. Copy it from the Xplorr Connect account form; there is no default."
  type        = string
  default     = null

  validation {
    condition     = var.trust_mode != "xplorr_principal" || (var.xplorr_service_account_email != null && can(regex("^[a-z][a-z0-9-]{4,29}@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", coalesce(var.xplorr_service_account_email, "none"))))
    error_message = "trust_mode = xplorr_principal needs xplorr_service_account_email, the service account address (ending in .iam.gserviceaccount.com) shown in the Xplorr Connect account form."
  }
}

variable "service_account_id" {
  description = "Account id (the part before the @) of the service account Xplorr uses."
  type        = string
  default     = "xplorr-reader"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "service_account_id must be 6 to 30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "service_account_display_name" {
  description = "Display name of the service account."
  type        = string
  default     = "Xplorr reader"
}

variable "create_key" {
  description = "Create a service account key in Terraform. Off by default: the private key would be stored in plain text in your Terraform state. Prefer running the gcloud command in the key_create_command output, then credentials_json_command. Ignored in xplorr_principal mode, which needs no key."
  type        = bool
  default     = false
}

variable "billing_dataset_id" {
  description = "The BigQuery dataset that receives the Cloud Billing export, in project_id."
  type        = string
  default     = "billing_export"

  validation {
    condition     = length(var.billing_dataset_id) <= 1024 && can(regex("^[A-Za-z0-9_]+$", var.billing_dataset_id))
    error_message = "billing_dataset_id may hold only letters, digits and underscores."
  }
}

variable "create_billing_dataset" {
  description = "Create the billing export dataset. Leave false if it exists already. Terraform cannot turn on the export itself; see the README."
  type        = bool
  default     = false
}

variable "bigquery_location" {
  description = "Location for the billing export dataset when create_billing_dataset = true, for example US, EU or europe-west1. A multi region (US or EU) backfills from the start of the previous month; a single region does not. When the dataset exists already, its real location is read from BigQuery and this value is ignored."
  type        = string
  default     = "US"
}

variable "billing_table" {
  description = "The standard usage cost export table, gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX. Leave null to let Xplorr use the gcp_billing_export_v1_* wildcard, which matches any standard export table in the dataset."
  type        = string
  default     = null

  validation {
    condition     = var.billing_table == null || can(regex("^[A-Za-z0-9_*-]+$", coalesce(var.billing_table, "x")))
    error_message = "billing_table may hold only letters, digits, underscores, hyphens and *."
  }
}

variable "bigquery_access_scope" {
  description = "Where BigQuery Data Viewer is granted: dataset (default, least privilege: the billing dataset plus additional_dataset_ids) or project (every dataset in project_id). The dataset must exist before apply when this is dataset."
  type        = string
  default     = "dataset"

  validation {
    condition     = contains(["dataset", "project"], var.bigquery_access_scope)
    error_message = "bigquery_access_scope must be dataset or project."
  }
}

variable "additional_dataset_ids" {
  description = "More datasets in project_id Xplorr may read with bigquery_access_scope = dataset, for example the FOCUS export or Carbon Footprint export dataset."
  type        = list(string)
  default     = []
}

variable "billing_account_id" {
  description = "Optional Cloud Billing account id (000000-000000-000000 format). When set, the service account gets Billing Account Viewer on it, which Xplorr uses for spend based committed use discount recommendations and the budget amount shown beside invoice reconciliation."
  type        = string
  default     = null

  validation {
    condition     = var.billing_account_id == null || can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", coalesce(var.billing_account_id, "x")))
    error_message = "billing_account_id must look like 000000-000000-000000 (uppercase hex)."
  }
}

variable "enable_org_level_grants" {
  description = <<-EOT
    Also grant scope_roles on organization_id and folder_ids. Off by default.
    WARNING: Xplorr currently reads only the connected project. Recommendations, inventory and audit logs are all read with projects/<project_id> scope, so organization or folder grants give Xplorr nothing today; they only widen what the key can read. Turn this on only if you want one service account ready for several projects, each connected to Xplorr separately.
  EOT
  type        = bool
  default     = false
}

variable "organization_id" {
  description = "Numeric organization id. Used only with enable_org_level_grants = true: the read roles in scope_roles are then also granted on the organization."
  type        = string
  default     = null

  validation {
    condition     = var.organization_id == null || can(regex("^[0-9]+$", coalesce(var.organization_id, "x")))
    error_message = "organization_id must be the numeric organization id."
  }

  validation {
    condition     = var.organization_id == null || var.enable_org_level_grants
    error_message = "organization_id is set but enable_org_level_grants is false. Set enable_org_level_grants = true to grant on the organization, or remove organization_id."
  }
}

variable "folder_ids" {
  description = "Numeric folder ids. Used only with enable_org_level_grants = true: the read roles in scope_roles are then also granted on each folder."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for f in var.folder_ids : can(regex("^[0-9]+$", f))])
    error_message = "folder_ids must be numeric folder ids, without the folders/ prefix."
  }

  validation {
    condition     = length(var.folder_ids) == 0 || var.enable_org_level_grants
    error_message = "folder_ids is set but enable_org_level_grants is false. Set enable_org_level_grants = true to grant on folders, or remove folder_ids."
  }
  validation {
    condition     = !var.enable_org_level_grants || var.organization_id != null || length(var.folder_ids) > 0
    error_message = "enable_org_level_grants = true needs organization_id or folder_ids."
  }
}

variable "scope_roles" {
  description = "Read roles granted on organization_id and folder_ids when enable_org_level_grants is true. BigQuery roles are not in it: they only matter on the project that holds the export."
  type        = list(string)
  default = [
    "roles/recommender.viewer",
    "roles/cloudasset.viewer",
    "roles/compute.viewer",
    "roles/logging.viewer",
    "roles/storage.bucketViewer",
  ]
}

variable "additional_project_roles" {
  description = "Extra roles to grant the service account on project_id."
  type        = list(string)
  default     = []
}

variable "enable_apis" {
  description = "Enable the APIs Xplorr calls in project_id. Enabling is never undone on destroy."
  type        = bool
  default     = true
}

# Opt-in write access. Off by default. A separate custom role bound to the
# same service account; the viewer roles above are never changed.

variable "enable_write_role" {
  description = "Create the xplorrWrite custom role in project_id and grant it to the Xplorr service account, so Xplorr can carry out the approved actions listed in write_actions. Off by default. The viewer roles are not changed."
  type        = bool
  default     = false
}

variable "write_actions" {
  description = "With enable_write_role. The action types the custom role may carry out. stop_idle_instance grants compute.instances.stop, and compute.instances.start to undo it."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_write_role || length(var.write_actions) > 0
    error_message = "enable_write_role = true needs at least one action type in write_actions."
  }

  validation {
    condition     = alltrue([for a in var.write_actions : contains(["stop_idle_instance"], a)])
    error_message = "write_actions may hold only stop_idle_instance on Google Cloud."
  }
}

variable "write_role_id" {
  description = "With enable_write_role. ID of the custom role in project_id (letters, digits, underscores and periods). A deleted custom role keeps its ID reserved for several weeks, so pick another ID if the old one is still reserved."
  type        = string
  default     = "xplorrWrite"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.]{3,64}$", var.write_role_id))
    error_message = "write_role_id must be 3 to 64 letters, digits, underscores or periods."
  }
}

variable "write_protect_tag" {
  description = "With enable_write_role. Optional. A Resource Manager tag key in namespaced form, for example my-project-id/xplorr-protect. The grant then carries an IAM condition, so instances tagged with that key and the value true are refused. The tag key and its value true must exist before apply. Labels cannot be used in IAM conditions; tags can. Null means no condition."
  type        = string
  default     = null

  validation {
    condition     = var.write_protect_tag == null || can(regex("^[a-z0-9][a-z0-9-]{0,62}/[A-Za-z0-9][A-Za-z0-9._-]{0,62}$", coalesce(var.write_protect_tag, "x/x")))
    error_message = "write_protect_tag must be a namespaced tag key such as my-project-id/xplorr-protect, or null."
  }
}
