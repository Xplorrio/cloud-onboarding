# Offline tests. The google provider is mocked, so nothing calls Google Cloud
# and no credentials are needed.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "xplorr-reader@my-project.iam.gserviceaccount.com"
      name  = "projects/my-project/serviceAccounts/xplorr-reader@my-project.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_project_iam_custom_role" {
    defaults = {
      name = "projects/my-project/roles/xplorrWrite"
    }
  }

  mock_data "google_bigquery_dataset" {
    defaults = {
      location = "US"
    }
  }

  mock_resource "google_service_account_key" {
    defaults = {
      # base64 of {"type":"service_account","project_id":"my-project"}
      private_key = "eyJ0eXBlIjoic2VydmljZV9hY2NvdW50IiwicHJvamVjdF9pZCI6Im15LXByb2plY3QifQ==" # gitleaks:allow (placeholder, decoded above)
    }
  }
}

override_resource {
  target = google_service_account.write[0]
  values = {
    email = "xplorr-write@my-project.iam.gserviceaccount.com"
    name  = "projects/my-project/serviceAccounts/xplorr-write@my-project.iam.gserviceaccount.com"
  }
}

variables {
  project_id = "my-project"
}

run "customer_principal_default" {
  command = apply

  assert {
    condition     = output.trust_mode == "customer_principal"
    error_message = "The default trust mode must be customer_principal."
  }

  assert {
    condition = length(setsubtract([
      "roles/bigquery.jobUser", "roles/recommender.viewer", "roles/cloudasset.viewer",
      "roles/compute.viewer", "roles/logging.viewer", "roles/storage.bucketViewer",
    ], keys(google_project_iam_member.xplorr))) == 0
    error_message = "A project role Xplorr needs is missing."
  }

  assert {
    condition     = !contains(keys(google_project_iam_member.xplorr), "roles/bigquery.dataViewer") && keys(google_bigquery_dataset_iam_member.xplorr) == ["billing_export"]
    error_message = "BigQuery Data Viewer must default to the billing dataset only."
  }

  assert {
    condition     = length(google_service_account_key.xplorr) == 0
    error_message = "No key may be created by default."
  }

  assert {
    condition     = output.xplorr_credentials_json == null
    error_message = "The credentials output must be empty without create_key."
  }

  assert {
    condition     = length(google_service_account_iam_member.xplorr_impersonation) == 0 && length(google_billing_account_iam_member.xplorr) == 0
    error_message = "No impersonation or billing account grant by default."
  }

  assert {
    condition     = output.xplorr_connect_form == { projectId = "my-project", billingDataset = "billing_export", bigqueryLocation = "US" }
    error_message = "The connect form output is wrong."
  }

  assert {
    condition     = strcontains(output.key_create_command, "xplorr-reader@my-project.iam.gserviceaccount.com") && strcontains(output.credentials_json_command, "jq --slurpfile key xplorr-key.json") && strcontains(output.credentials_json_command, "terraform output -json xplorr_connect_form")
    error_message = "The key command or the credentials command is wrong."
  }

  assert {
    condition     = !contains(keys(google_project_service.xplorr), "compute.googleapis.com") && contains(keys(google_project_service.xplorr), "recommender.googleapis.com")
    error_message = "The API set is wrong."
  }
}

run "opt_in_key_and_billing_account" {
  command = apply

  variables {
    create_key             = true
    create_billing_dataset = true
    billing_account_id     = "000000-000000-000000"
    billing_table          = "gcp_billing_export_v1_000000_000000_000000"
    bigquery_location      = "EU"
  }

  assert {
    condition     = length(google_service_account_key.xplorr) == 1 && output.credentials_json_command == null
    error_message = "create_key must create a key, and then no merge command is needed."
  }

  assert {
    condition     = jsondecode(output.xplorr_credentials_json).keyfileJson.type == "service_account" && jsondecode(output.xplorr_credentials_json).bigqueryLocation == "EU"
    error_message = "The credentials output must wrap the key file."
  }

  assert {
    condition     = google_billing_account_iam_member.xplorr[0].role == "roles/billing.viewer"
    error_message = "billing_account_id must grant Billing Account Viewer."
  }

  assert {
    condition     = contains(keys(google_project_service.xplorr), "billingbudgets.googleapis.com")
    error_message = "The Budget API must be enabled with a billing account."
  }
}

run "xplorr_principal_is_keyless" {
  command = apply

  variables {
    trust_mode                   = "xplorr_principal"
    xplorr_service_account_email = "xplorr-connector@example-project.iam.gserviceaccount.com"
    create_key                   = true
  }

  assert {
    condition     = length(google_service_account_key.xplorr) == 0 && output.key_create_command == null
    error_message = "xplorr_principal must never create a key."
  }

  assert {
    condition     = google_service_account_iam_member.xplorr_impersonation[0].role == "roles/iam.serviceAccountTokenCreator" && google_service_account_iam_member.xplorr_impersonation[0].member == "serviceAccount:xplorr-connector@example-project.iam.gserviceaccount.com"
    error_message = "Xplorr's service account must be allowed to impersonate."
  }

  assert {
    condition     = contains(keys(google_project_service.xplorr), "iamcredentials.googleapis.com")
    error_message = "The IAM Service Account Credentials API must be enabled."
  }
}

run "xplorr_principal_needs_email" {
  command = plan

  variables {
    trust_mode = "xplorr_principal"
  }

  expect_failures = [var.xplorr_service_account_email]
}

run "existing_dataset_location_is_read" {
  command = apply

  override_data {
    target = data.google_bigquery_dataset.existing[0]
    values = {
      location = "europe-west1"
    }
  }

  variables {
    bigquery_location = "US"
  }

  assert {
    condition     = output.xplorr_connect_form.bigqueryLocation == "europe-west1"
    error_message = "An existing dataset's real location must win over the input."
  }
}

run "org_grants_off_by_default" {
  command = plan

  variables {
    organization_id = "000000000000"
  }

  expect_failures = [var.organization_id]
}

run "org_grants_need_a_target" {
  command = plan

  variables {
    enable_org_level_grants = true
  }

  expect_failures = [var.folder_ids]
}

run "organization_and_folders" {
  command = apply

  variables {
    enable_org_level_grants = true
    organization_id         = "000000000000"
    folder_ids              = ["111111111111"]
    bigquery_access_scope   = "project"
  }

  assert {
    condition     = length(google_organization_iam_member.xplorr) == 5 && length(google_folder_iam_member.xplorr) == 5
    error_message = "Each scope role must be granted on the organization and the folder."
  }

  assert {
    condition     = contains(keys(google_project_iam_member.xplorr), "roles/bigquery.dataViewer") && length(google_bigquery_dataset_iam_member.xplorr) == 0
    error_message = "bigquery_access_scope = project must grant Data Viewer on the project."
  }
}

run "write_role_off_by_default" {
  command = apply

  assert {
    condition     = length(google_project_iam_custom_role.write) == 0 && length(google_project_iam_member.write) == 0 && output.xplorr_write_access == null
    error_message = "The write role must be off by default."
  }
}

run "write_role_stop_instance" {
  command = apply

  variables {
    enable_write_role = true
    write_actions     = ["stop_idle_instance"]
  }

  assert {
    condition     = google_project_iam_custom_role.write[0].permissions == toset(["compute.instances.start", "compute.instances.stop"])
    error_message = "stop_idle_instance must grant only compute.instances.stop and compute.instances.start."
  }

  assert {
    condition     = google_project_iam_member.write[0].role == "projects/my-project/roles/xplorrWrite" && google_project_iam_member.write[0].member == "serviceAccount:xplorr-write@my-project.iam.gserviceaccount.com"
    error_message = "The custom role must be granted to the separate write service account."
  }

  assert {
    condition     = google_service_account.write[0].account_id == "xplorr-write" && output.write_service_account_email == "xplorr-write@my-project.iam.gserviceaccount.com" && output.xplorr_write_access.service_account == "xplorr-write@my-project.iam.gserviceaccount.com"
    error_message = "Write access must use its own service account, xplorr-write."
  }

  assert {
    condition     = alltrue([for k, v in google_project_iam_member.xplorr : v.member == "serviceAccount:xplorr-reader@my-project.iam.gserviceaccount.com"])
    error_message = "The viewer roles must stay on the read service account."
  }

  assert {
    condition     = length(google_service_account_key.write) == 0 && strcontains(output.write_key_create_command, "--iam-account=xplorr-write@my-project.iam.gserviceaccount.com")
    error_message = "No write key by default; the output must give the command for the write service account."
  }

  assert {
    condition     = length(google_project_iam_member.write[0].condition) == 0
    error_message = "Without write_protect_tag the grant has no condition."
  }

  assert {
    condition     = !contains(keys(google_project_iam_member.xplorr), "projects/my-project/roles/xplorrWrite")
    error_message = "The viewer grants must not change."
  }
}

run "write_role_protect_tag" {
  command = apply

  variables {
    enable_write_role = true
    write_actions     = ["stop_idle_instance"]
    write_protect_tag = "my-project/xplorr-protect"
  }

  assert {
    condition     = google_project_iam_member.write[0].condition[0].expression == "!resource.matchTag('my-project/xplorr-protect', 'true')"
    error_message = "write_protect_tag must add a condition refusing tagged instances."
  }
}

run "write_role_needs_actions" {
  command = plan

  variables {
    enable_write_role = true
  }

  expect_failures = [var.write_actions]
}

run "bad_protect_tag_rejected" {
  command = plan

  variables {
    enable_write_role = true
    write_actions     = ["stop_idle_instance"]
    write_protect_tag = "xplorr:protect"
  }

  expect_failures = [var.write_protect_tag]
}

run "write_role_keyless_impersonation" {
  command = apply

  variables {
    trust_mode                         = "xplorr_principal"
    xplorr_service_account_email       = "xplorr-connector@example-project.iam.gserviceaccount.com"
    enable_write_role                  = true
    write_actions                      = ["stop_idle_instance"]
    xplorr_write_service_account_email = "xplorr-actions@example-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = google_service_account_iam_member.xplorr_write_impersonation[0].member == "serviceAccount:xplorr-actions@example-project.iam.gserviceaccount.com" && google_service_account_iam_member.xplorr_write_impersonation[0].service_account_id == "projects/my-project/serviceAccounts/xplorr-write@my-project.iam.gserviceaccount.com"
    error_message = "Only Xplorr's actions service account may impersonate the write service account."
  }

  assert {
    condition     = google_service_account_iam_member.xplorr_impersonation[0].member == "serviceAccount:xplorr-connector@example-project.iam.gserviceaccount.com"
    error_message = "The read service account's impersonation must not change."
  }

  assert {
    condition     = output.write_key_create_command == null
    error_message = "Keyless write access needs no key."
  }
}

run "write_role_keyless_needs_actions_principal" {
  command = plan

  variables {
    trust_mode                   = "xplorr_principal"
    xplorr_service_account_email = "xplorr-connector@example-project.iam.gserviceaccount.com"
    enable_write_role            = true
    write_actions                = ["stop_idle_instance"]
  }

  expect_failures = [var.xplorr_write_service_account_email]
}

run "write_service_account_must_differ" {
  command = plan

  variables {
    enable_write_role        = true
    write_actions            = ["stop_idle_instance"]
    write_service_account_id = "xplorr-reader"
  }

  expect_failures = [var.write_service_account_id]
}

