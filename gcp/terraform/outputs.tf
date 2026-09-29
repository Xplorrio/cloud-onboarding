locals {
  connect_fields = { for k, v in {
    projectId        = var.project_id
    billingDataset   = var.billing_dataset_id
    billingTable     = var.billing_table
    bigqueryLocation = local.bigquery_location
    billingAccountId = var.billing_account_id
  } : k => v if v != null }

  key_file_name         = "xplorr-key.json"
  credentials_file_name = "xplorr-credentials.json"
  key_command           = "gcloud iam service-accounts keys create ${local.key_file_name} --iam-account=${google_service_account.xplorr.email} --project=${var.project_id}"

  # Merges the downloaded key file into the connect fields as keyfileJson and
  # writes the complete Credentials (JSON) to a file, so the private key is
  # never printed to the terminal. Run it where terraform output works (the
  # root module directory), with the key file in the same directory.
  credentials_command = "(umask 077 && terraform output -json xplorr_connect_form | jq --slurpfile key ${local.key_file_name} '. + {keyfileJson: $key[0]}' > ${local.credentials_file_name})"
}

output "trust_mode" {
  description = "The trust mode this module was applied with."
  value       = var.trust_mode
}

output "service_account_email" {
  description = "The service account Xplorr signs in as (customer_principal) or impersonates (xplorr_principal)."
  value       = google_service_account.xplorr.email
}

output "xplorr_connect_form" {
  description = "The non secret fields of the Xplorr Connect account form (Provider: Google Cloud Platform). GCP project ID is projectId; the rest go into the Credentials (JSON) object beside keyfileJson. billingTable is left out when null, so Xplorr uses the gcp_billing_export_v1_* wildcard. Read it as JSON with: terraform output -json xplorr_connect_form"
  value       = local.connect_fields
}

output "key_create_command" {
  description = "Run this yourself to create the service account key, so the private key never lands in Terraform state. Not needed in xplorr_principal mode."
  value       = local.keyless ? null : local.key_command
}

output "credentials_json_command" {
  description = "Run after key_create_command. Writes the complete Credentials (JSON) for Xplorr to xplorr-credentials.json by merging the key file into xplorr_connect_form with jq. Paste that file's contents into Xplorr, then delete both files. Not needed in xplorr_principal mode or with create_key."
  value       = local.keyless || local.create_key ? null : local.credentials_command
}

output "xplorr_credentials_json" {
  description = "Only with create_key = true: the complete Credentials (JSON) for Xplorr, key included. Write it to a file with: terraform output -raw xplorr_credentials_json > xplorr-credentials.json. The same key is in your state in plain text."
  sensitive   = true
  value = local.create_key ? jsonencode(merge(local.connect_fields, {
    keyfileJson = jsondecode(base64decode(google_service_account_key.xplorr[0].private_key))
  })) : null
}

output "impersonation" {
  description = "Only with trust_mode = xplorr_principal (coming soon): the Xplorr principal allowed to impersonate service_account_email. Xplorr does not accept keyless GCP connections yet."
  value = local.keyless ? {
    xplorr_principal        = var.xplorr_service_account_email
    target_service_account  = google_service_account.xplorr.email
    role                    = "roles/iam.serviceAccountTokenCreator"
    available_in_xplorr_now = false
  } : null
}

output "next_steps" {
  description = "What is left to do by hand."
  value = join("\n", compact([
    "1. Turn on Billing > Billing export > BigQuery export > Standard usage cost (and Detailed usage cost for per resource costs) into ${var.project_id}.${var.billing_dataset_id}, if it is not on already. Terraform cannot do this step.",
    local.keyless ? "2. Keyless GCP onboarding is coming soon; keep this service account until the Xplorr form offers it." : (local.create_key ? "2. terraform output -raw xplorr_credentials_json > ${local.credentials_file_name}" : "2. ${local.key_command}"),
    local.keyless || local.create_key ? null : "3. ${local.credentials_command}",
    local.keyless ? null : "${local.create_key ? "3" : "4"}. In Xplorr, Infrastructure > Cloud Accounts > Connect account > Google Cloud Platform. GCP project ID: ${var.project_id}. Credentials (JSON): the contents of ${local.credentials_file_name}. Then delete ${local.credentials_file_name}${local.create_key ? "" : " and ${local.key_file_name}"}.",
    var.enable_write_role ? "Write access (opt in): the custom role ${var.write_role_id} may carry out ${join(", ", var.write_actions)} in ${var.project_id}. Xplorr uses it only after a person in your Xplorr organization approves an action. Print the values with: terraform output -json xplorr_write_access" : null,
  ]))
}

output "xplorr_write_access" {
  description = "With enable_write_role. What Xplorr asks for when you turn on write access: the custom role ID, the service account it is granted to, the action types and the permissions. Null when the write role is off."
  value = var.enable_write_role ? {
    custom_role_id  = google_project_iam_custom_role.write[0].name
    service_account = google_service_account.xplorr.email
    actions         = var.write_actions
    permissions     = local.write_role_permissions
    protect_tag     = var.write_protect_tag
  } : null
}

