# The Google Cloud identity Xplorr reads with, and nothing else.
#
# Every role here is a viewer role. What each one is for, taken from the
# Xplorr cloud-sync-service GCP providers:
#
#   roles/bigquery.dataViewer    billing export tables (costs, per resource
#                                costs, commitments, FOCUS and carbon exports)
#   roles/bigquery.jobUser       running those queries in project_id
#   roles/recommender.viewer     idle VM, idle disk, idle Cloud SQL, machine
#                                type and usage based CUD recommendations
#   roles/cloudasset.viewer      the resource inventory (searchAllResources)
#   roles/compute.viewer         committed use discounts (regionCommitments),
#                                and the inventory fallback
#   roles/storage.bucketViewer   the inventory fallback's bucket listing, used
#                                when the Cloud Asset API is denied
#   roles/logging.viewer         Admin Activity audit logs, for anomaly root
#                                cause analysis
#   roles/billing.viewer         on the billing account, only when
#                                billing_account_id is set: spend based CUD
#                                recommendations and the Budget API hint

locals {
  keyless    = var.trust_mode == "xplorr_principal"
  create_key = var.create_key && !local.keyless
  member     = "serviceAccount:${google_service_account.xplorr.email}"

  project_roles = distinct(concat(
    [
      "roles/bigquery.jobUser",
      "roles/recommender.viewer",
      "roles/cloudasset.viewer",
      "roles/compute.viewer",
      "roles/logging.viewer",
      "roles/storage.bucketViewer",
    ],
    var.bigquery_access_scope == "project" ? ["roles/bigquery.dataViewer"] : [],
    var.additional_project_roles,
  ))

  # The location Xplorr must query in. For an existing dataset it is read from
  # BigQuery, so a wrong bigquery_location input cannot break the connection.
  bigquery_location = var.create_billing_dataset ? var.bigquery_location : data.google_bigquery_dataset.existing[0].location

  dataset_ids = var.bigquery_access_scope == "dataset" ? distinct(concat([var.billing_dataset_id], var.additional_dataset_ids)) : []

  # compute.googleapis.com is left out on purpose: enabling it on a project
  # that never used Compute Engine creates the default VPC network. Without
  # it there are no commitments or VMs to read anyway.
  apis = var.enable_apis ? toset(concat(
    [
      "bigquery.googleapis.com",
      "recommender.googleapis.com",
      "cloudasset.googleapis.com",
      "logging.googleapis.com",
    ],
    var.billing_account_id != null ? ["billingbudgets.googleapis.com"] : [],
    local.keyless ? ["iamcredentials.googleapis.com"] : [],
  )) : toset([])

  # The opt-in write role's permissions per action type. Reads of the
  # instance's state come from roles/compute.viewer above.
  write_permissions = {
    stop_idle_instance = ["compute.instances.stop", "compute.instances.start"]
  }
  write_role_permissions = sort(distinct(flatten([for a in var.write_actions : local.write_permissions[a]])))

  scope_grants = !var.enable_org_level_grants ? {} : merge(
    var.organization_id == null ? {} : {
      for role in var.scope_roles : "organizations/${var.organization_id}|${role}" => {
        kind = "organization", id = var.organization_id, role = role
      }
    },
    {
      for pair in setproduct(var.folder_ids, var.scope_roles) : "folders/${pair[0]}|${pair[1]}" => {
        kind = "folder", id = pair[0], role = pair[1]
      }
    },
  )
}

resource "google_project_service" "xplorr" {
  for_each = local.apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "xplorr" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
  description  = "Read only access for Xplorr cloud cost management (${var.trust_mode})."
}

resource "google_project_iam_member" "xplorr" {
  for_each = toset(local.project_roles)

  project = var.project_id
  role    = each.value
  member  = local.member
}

data "google_bigquery_dataset" "existing" {
  count = var.create_billing_dataset ? 0 : 1

  project    = var.project_id
  dataset_id = var.billing_dataset_id
}

resource "google_bigquery_dataset" "billing_export" {
  count = var.create_billing_dataset ? 1 : 0

  project       = var.project_id
  dataset_id    = var.billing_dataset_id
  location      = var.bigquery_location
  friendly_name = "Cloud Billing export"
  description   = "Cloud Billing export to BigQuery, read by Xplorr. Turn the export on in the console: Billing, Billing export, BigQuery export."

  # No access blocks: when the export is turned on Google adds its own export
  # service account as an owner of this dataset, and an access block here
  # would remove it on the next apply.

  depends_on = [google_project_service.xplorr]
}

resource "google_bigquery_dataset_iam_member" "xplorr" {
  for_each = toset(local.dataset_ids)

  project    = var.project_id
  dataset_id = each.value
  role       = "roles/bigquery.dataViewer"
  member     = local.member

  depends_on = [google_bigquery_dataset.billing_export]
}

resource "google_billing_account_iam_member" "xplorr" {
  count = var.billing_account_id != null ? 1 : 0

  billing_account_id = var.billing_account_id
  role               = "roles/billing.viewer"
  member             = local.member
}

resource "google_organization_iam_member" "xplorr" {
  for_each = { for k, v in local.scope_grants : k => v if v.kind == "organization" }

  org_id = each.value.id
  role   = each.value.role
  member = local.member
}

resource "google_folder_iam_member" "xplorr" {
  for_each = { for k, v in local.scope_grants : k => v if v.kind == "folder" }

  folder = "folders/${each.value.id}"
  role   = each.value.role
  member = local.member
}

# xplorr_principal (coming soon): Xplorr's service account may mint tokens for
# this one service account only, never for the rest of the project. Google
# documents granting the role on the single service account rather than on
# the project, because a project level grant lets the holder impersonate every
# service account in it.
resource "google_service_account_iam_member" "xplorr_impersonation" {
  count = local.keyless ? 1 : 0

  service_account_id = google_service_account.xplorr.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${var.xplorr_service_account_email}"
}

# Opt in only. The private key ends up in plain text in the Terraform state.
resource "google_service_account_key" "xplorr" {
  count = local.create_key ? 1 : 0

  service_account_id = google_service_account.xplorr.name
}

# Opt-in write access: a separate service account, and a custom role holding
# only the permissions of the listed action types, granted to that service
# account only on project_id. The optional condition refuses instances tagged
# write_protect_tag = true. The read service account never gets the role.
resource "google_service_account" "write" {
  count = var.enable_write_role ? 1 : 0

  project      = var.project_id
  account_id   = var.write_service_account_id
  display_name = "Xplorr write"
  description  = "Opt-in write access for Xplorr approved actions (${var.trust_mode}). Separate from the read service account."
}
resource "google_project_iam_custom_role" "write" {
  count = var.enable_write_role ? 1 : 0

  project     = var.project_id
  role_id     = var.write_role_id
  title       = "Xplorr write"
  description = "Opt-in write access for Xplorr approved actions: ${join(", ", var.write_actions)}. Created by https://github.com/Xplorrio/cloud-onboarding"
  permissions = local.write_role_permissions
}

resource "google_project_iam_member" "write" {
  count = var.enable_write_role ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.write[0].name
  member  = "serviceAccount:${google_service_account.write[0].email}"

  dynamic "condition" {
    for_each = var.write_protect_tag != null ? [1] : []
    content {
      title       = "not-protected"
      description = "Refuse instances tagged ${var.write_protect_tag} = true"
      expression  = "!resource.matchTag('${var.write_protect_tag}', 'true')"
    }
  }
}

# xplorr_principal: Xplorr's separate actions service account may mint tokens
# for the write service account only, just as the read service account is
# impersonated by Xplorr's sync service account.
resource "google_service_account_iam_member" "xplorr_write_impersonation" {
  count = var.enable_write_role && local.keyless ? 1 : 0

  service_account_id = google_service_account.write[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${var.xplorr_write_service_account_email}"
}

# Opt in only, with create_key, like the read key. The private key ends up in
# plain text in the Terraform state.
resource "google_service_account_key" "write" {
  count = var.enable_write_role && local.create_key ? 1 : 0

  service_account_id = google_service_account.write[0].name
}

