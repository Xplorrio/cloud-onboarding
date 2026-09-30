# Google Cloud onboarding for Xplorr

Creates the one Google Cloud identity Xplorr reads with, grants it read only
roles, and prints what the Xplorr **Connect account** form asks for. Two ways
to run it, which create the same thing:

| Tool | Path | Good for |
|---|---|---|
| Terraform | [`terraform/`](terraform/) | Teams that keep IAM in code |
| gcloud | [`gcloud.sh`](gcloud.sh) | A one off setup from Cloud Shell or a laptop |

Every role is a viewer role. Xplorr needs read only access and never changes
resources in your projects.

## What it creates

In the project you connect (the one holding the billing export dataset):

- A service account, `xplorr-reader` by default
- These roles for it:

| Role | Where | What Xplorr uses it for |
|---|---|---|
| BigQuery Data Viewer (`roles/bigquery.dataViewer`) | The billing export dataset (or the whole project, see below) | Costs, per resource costs, commitment utilization and coverage, FOCUS and carbon exports |
| BigQuery Job User (`roles/bigquery.jobUser`) | Project | Running those queries. They run in, and are billed to, this project |
| Recommender Viewer (`roles/recommender.viewer`) | Project | Idle VM, idle disk, idle Cloud SQL, machine type and usage based committed use discount (CUD) recommendations |
| Cloud Asset Viewer (`roles/cloudasset.viewer`) | Project | The full resource inventory |
| Compute Viewer (`roles/compute.viewer`) | Project | Committed use discounts, and the inventory fallback |
| Storage Bucket Viewer (`roles/storage.bucketViewer`) | Project | The inventory fallback's bucket listing, used only when the Cloud Asset API is denied |
| Logs Viewer (`roles/logging.viewer`) | Project | Admin Activity audit logs, for upcoming anomaly root cause analysis |
| Billing Account Viewer (`roles/billing.viewer`) | Billing account, **only if you pass its id** | Spend based CUD recommendations, and the budget amount shown beside invoice reconciliation |

- These APIs enabled: BigQuery, Recommender, Cloud Asset, Cloud Logging, plus
  Cloud Billing Budget when you pass a billing account, and IAM Service
  Account Credentials in `xplorr_principal` mode. The Compute Engine API is
  **not** enabled: enabling it on a project that never used Compute Engine
  creates the default network, and without it there are no VMs or
  commitments to read.
- Optionally the billing export dataset itself.
- Only if you opt in (`enable_org_level_grants`, `--enable-org-level-grants`): the
  same read roles on your organization or folders. Xplorr reads only the
  connected project today, so this is off by default.

BigQuery Data Viewer is granted on the billing dataset only by default. If
you also use the FOCUS or Carbon Footprint export, add those datasets
(`additional_dataset_ids`, or `--extra-dataset`), or grant it on the whole
project (`bigquery_access_scope = "project"`, or `--bigquery-scope project`).

## Before you start

Tools:

- Terraform path: Terraform 1.10 or later (tested with 1.16), the
  `hashicorp/google` provider 8.x (`>= 8.0, < 9.0`, tested with 8.4.0), and
  `jq` to build the Credentials (JSON) file. Sign in with
  `gcloud auth application-default login`.
- gcloud path: the Google Cloud SDK (`gcloud` and `bq`) and `python3`, for
  example in [Cloud Shell](https://shell.cloud.google.com). `jq` is optional.

Permissions for the person running it:

- In the project: permission to create service accounts, enable services and
  grant IAM roles (Owner, or Service Account Admin plus Project IAM Admin
  plus Service Usage Admin).
- To turn on the billing export: Billing Account Administrator or Billing
  Account Costs Manager on the billing account, and BigQuery User on the
  project.
- For the billing account grant: Billing Account Administrator.
- For organization or folder grants: Organization Administrator, or Folder
  IAM Admin on each folder.

## Step 1: turn on the Cloud Billing export to BigQuery

This one step is manual. Google has no API, gcloud command or Terraform
resource for it: the Google provider (checked in 8.4.0) has
`google_billing_account_iam_member`, `google_billing_budget` and friends, but
nothing that configures the BigQuery export, and
[Google's setup guide](https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-setup)
covers only the console. What the code here can do is create the dataset.

1. **Create the dataset** (skip if the export is already on). Either set
   `create_billing_dataset = true` in Terraform, pass `--create-dataset` to
   `gcloud.sh`, or run:

   ```bash
   bq mk --dataset --location=US my-project-id:billing_export
   ```

   Choose the location with care. A multi region dataset (`US` or `EU`)
   receives billing data from the start of the previous month when you first
   turn the export on. A single region dataset (such as `europe-west1`) only
   receives data from the day you turn it on. The project must be linked to
   the billing account whose costs you export.

2. **Point the export at it.** In the console go to **Billing > Billing
   export > BigQuery export**. Edit **Standard usage cost**, pick the project
   and dataset, and save. Xplorr reads this table for every cost figure.

3. **Turn on Detailed usage cost too**, into the same dataset, if you want per
   resource costs. Xplorr reads the detailed table
   (`gcp_billing_export_resource_v1_...`) for those; the standard export has
   no resource column.

4. **Wait for the first table**, `gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX`
   (your billing account id with underscores). That can take a few hours.
   Connect after it exists: the Xplorr connect check queries it.

When the export is turned on, Google adds its own export service account as
an owner of the dataset. Leave it there. The Terraform module never manages
the dataset's access list, and `gcloud.sh` only appends to it, so neither
removes that entry.

Pricing data export is not needed by Xplorr.

## Step 2a: Terraform

```bash
cd terraform/examples/project
cp terraform.tfvars.example terraform.tfvars   # then edit it
terraform init
terraform apply
```

Then create the key yourself, so it never lands in Terraform state, and merge
it into the Credentials (JSON) file. Both commands are also printed by
`terraform output -raw next_steps`:

```bash
# 1. Create the key file xplorr-key.json
$(terraform output -raw key_create_command)

# 2. Merge it into the connect fields as keyfileJson. Writes
#    xplorr-credentials.json without printing the private key.
(umask 077 && terraform output -json xplorr_connect_form \
  | jq --slurpfile key xplorr-key.json '. + {keyfileJson: $key[0]}' > xplorr-credentials.json)
```

`terraform output -json xplorr_connect_form` alone shows the non secret
fields as clean JSON.

### Using the module from your own code

From a clone of this repository, use a local path:

```hcl
module "xplorr" {
  source = "./cloud-onboarding/gcp/terraform" # path to your clone

  project_id         = "my-project-id"
  billing_dataset_id = "billing_export"
  billing_account_id = "000000-000000-000000" # optional
}
```

Or a git source pinned to a release tag:

```hcl
module "xplorr" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//gcp/terraform?ref=v0.0.1"

  project_id         = "my-project-id"
  billing_dataset_id = "billing_export"
}
```

The module declares no provider block; configure `google` in the caller, as
the examples do.

Examples:

- [`examples/project`](terraform/examples/project): one project.
- [`examples/organization`](terraform/examples/organization): the same, with
  organization or folder grants available behind
  `enable_org_level_grants` (off by default; see
  [Organization and folder grants](#organization-and-folder-grants)).

### Creating the key in Terraform (not recommended)

`create_key = true` creates a `google_service_account_key`, and
`terraform output -raw xplorr_credentials_json > xplorr-credentials.json`
writes the complete Credentials JSON, key included. **The private key is
stored in plain text in your Terraform state**, and anyone who can read the
state can read your billing data. Use it only with an encrypted, access
controlled backend, and prefer the gcloud command above. Many organizations
block key creation with the `iam.disableServiceAccountKeyCreation` policy; if
yours does, both ways fail until an exception is made for this project.

### Inputs

| Name | Default | Description |
|---|---|---|
| `project_id` | required | Project that holds the billing export |
| `trust_mode` | `customer_principal` | `customer_principal` or `xplorr_principal` (coming soon) |
| `xplorr_service_account_email` | `null` | Xplorr's service account, required for `xplorr_principal` |
| `service_account_id` | `xplorr-reader` | Service account id |
| `create_key` | `false` | Create the key in Terraform (lands in state) |
| `billing_dataset_id` | `billing_export` | Billing export dataset |
| `create_billing_dataset` | `false` | Create that dataset |
| `bigquery_location` | `US` | Location when creating the dataset. For an existing dataset the real location is read from BigQuery |
| `billing_table` | `null` | Pin the standard export table; null uses the `gcp_billing_export_v1_*` wildcard |
| `bigquery_access_scope` | `dataset` | `dataset` or `project` for BigQuery Data Viewer |
| `additional_dataset_ids` | `[]` | More datasets Xplorr may read |
| `billing_account_id` | `null` | Grants Billing Account Viewer on it |
| `enable_org_level_grants` | `false` | Allow grants on `organization_id` and `folder_ids`. Xplorr reads only the connected project today |
| `organization_id` | `null` | With `enable_org_level_grants`: also grant `scope_roles` on the organization |
| `folder_ids` | `[]` | With `enable_org_level_grants`: also grant `scope_roles` on these folders |
| `scope_roles` | the five project read roles | Roles granted on the organization and folders |
| `additional_project_roles` | `[]` | Extra project roles |
| `enable_apis` | `true` | Enable the APIs listed above |

### Outputs

| Name | Description |
|---|---|
| `service_account_email` | The service account |
| `xplorr_connect_form` | `projectId`, `billingDataset`, `billingTable`, `bigqueryLocation`, `billingAccountId`: the non secret Credentials (JSON) fields |
| `key_create_command` | The gcloud command that creates the key |
| `credentials_json_command` | The jq command that merges the key into `xplorr-credentials.json` |
| `xplorr_credentials_json` | Sensitive; only with `create_key = true` |
| `impersonation` | Only in `xplorr_principal` mode |
| `next_steps` | What is left to do by hand |

## Step 2b: gcloud

```bash
./gcloud.sh --project my-project-id
```

Common options:

```bash
./gcloud.sh --project my-project-id \
  --location EU --create-dataset \
  --billing-account 000000-000000-000000
```

`./gcloud.sh --help` lists them all. The script is safe to run again: it
skips what exists, only adds IAM bindings, reads the dataset's real location
and finds the export table once it exists. At the end it writes
`xplorr-connect-form.json` (no secret) and, when the key file exists,
`xplorr-credentials.json` with the key merged in as `keyfileJson`. It never
prints the private key.

It does not create a key unless you pass `--create-key`, and then never twice
(it will not overwrite an existing key file). Without `--create-key`, it
prints the `gcloud iam service-accounts keys create` command and the jq
command that builds `xplorr-credentials.json`; or run the script again once
the key file exists.

## Step 3: connect in Xplorr

In Xplorr go to **Infrastructure > Cloud Accounts > Connect account** and set
**Provider** to **Google Cloud Platform**.

- **GCP project ID**: `projectId`, the project holding the export dataset.
- **Credentials (JSON)**: the contents of `xplorr-credentials.json`. Its shape:

```json
{
  "projectId": "my-project-id",
  "billingDataset": "billing_export",
  "billingTable": "gcp_billing_export_v1_000000_000000_000000",
  "bigqueryLocation": "US",
  "billingAccountId": "000000-000000-000000",
  "keyfileJson": { "type": "service_account", "...": "the rest of the key file" }
}
```

| Field | Required | Notes |
|---|---|---|
| `projectId` | Yes | The project holding the export dataset |
| `keyfileJson` | Yes | The key file, as an object or a string |
| `billingDataset` | No, default `billing_export` | `datasetId` is accepted too |
| `billingTable` | No, default `gcp_billing_export_v1_*` | `tableId` is accepted too |
| `bigqueryLocation` | Yes unless the dataset is in `US` | Must match the dataset exactly, for example `EU` or `europe-west1` |
| `billingAccountId` | No | Only with the Billing Account Viewer grant |
| `regions` | No | Up to three regions to read idle resource and machine type recommendations from, for example `["us-central1", "europe-west1"]`. Default `["us-central1", "us-east1", "europe-west1"]`. Committed use recommendations also cover every region the project spends in. Add it to the Credentials (JSON) by hand; the templates do not output it |

Click **Test connection**, then **Connect account**. Then delete
`xplorr-credentials.json` and `xplorr-key.json`. **Test connection** checks
the key and the BigQuery grants only; Recommender, Cloud Asset and Logging
access is first used by the first sync, and a missing role there shows as
missing data, not as an error.

## Trust modes

`trust_mode` (Terraform) or `--trust-mode` (gcloud):

- **`customer_principal`** (default, works today). Xplorr signs in as the
  service account with a JSON key you create and paste into Xplorr.
- **`xplorr_principal`** (coming soon, not live in Xplorr yet: the Connect
  account form still requires a key file). No key at all. The same service
  account and roles are created, and Xplorr's own service account is given
  Service Account Token Creator (`roles/iam.serviceAccountTokenCreator`) on
  **that one service account only**, so Xplorr can impersonate it for short
  lived tokens. You pass Xplorr's service account email
  (`xplorr_service_account_email`, or `--xplorr-principal`); it will be shown
  in the Connect account form when the mode ships, and there is no default.

Why impersonation rather than granting the roles straight to Xplorr's
service account: Google recommends impersonation over keys because each use
is logged with the principal who impersonated
([service account best practices](https://docs.cloud.google.com/iam/docs/best-practices-service-accounts)),
and recommends granting Token Creator on the individual service account
rather than the project, since a project grant lets the holder impersonate
every service account in it (same page). All roles stay on an identity in
your project, so revoking Xplorr is one binding, and API calls are made by a
service account in your project, whereas a service account from another
project usually needs each API enabled in both projects
([service account overview](https://docs.cloud.google.com/iam/docs/service-account-overview)).
Google does not publish a pattern specific to third party vendors across
organizations; this follows the documented general guidance.

If your organization enforces domain restricted sharing
(`iam.allowedPolicyMemberDomains`), the Token Creator grant to an outside
service account is refused until Xplorr's organization is allowed
([restricting identities by domain](https://docs.cloud.google.com/organization-policy/restrict-domains)).

## Organization and folder grants

Off by default. **Xplorr currently reads only the connected project**:
recommendations, inventory and audit logs are all read with
`projects/<project_id>` scope, and the connect check queries the billing
export in that same project. Organization or folder grants therefore give
Xplorr nothing today; they only widen what the key could read.

If you still want one service account ready for several projects (each
connected to Xplorr as its own cloud account, and each holding a billing
export dataset), set `enable_org_level_grants = true` with `organization_id`
or `folder_ids` in Terraform, or pass `--enable-org-level-grants` with
`--organization` or `--folder` to `gcloud.sh`. That grants the read roles
(Recommender, Cloud Asset, Compute, Logging and Storage Bucket Viewer) on
those scopes. BigQuery roles stay on the export project. Setting an
organization or folder without the opt in fails with an error rather than
being ignored.

## Rotating the key

1. Create a new key:
   `gcloud iam service-accounts keys create xplorr-key.json --iam-account=xplorr-reader@my-project-id.iam.gserviceaccount.com --project=my-project-id`
2. Build `xplorr-credentials.json` again (the jq command in Step 2a, or re-run
   `gcloud.sh` with the same options).
3. In Xplorr, open **Infrastructure > Cloud Accounts**, click **Update
   credentials** on the account's row, paste the new Credentials (JSON) and
   save. The dataset, table and location are kept.
4. Once the next sync succeeds, delete the old key:

   ```bash
   gcloud iam service-accounts keys list \
     --iam-account=xplorr-reader@my-project-id.iam.gserviceaccount.com --managed-by=user
   gcloud iam service-accounts keys delete KEY_ID \
     --iam-account=xplorr-reader@my-project-id.iam.gserviceaccount.com
   ```

5. Delete the local key and credentials files.

With `create_key = true`, rotate by replacing the resource:
`terraform apply -replace='module.xplorr.google_service_account_key.xplorr[0]'`,
then update the credentials in Xplorr the same way.

## Removing everything

First delete the account in Xplorr (**Infrastructure > Cloud Accounts**, the
account's row).

**Terraform:** `terraform destroy` removes the service account, its key if
Terraform made one, and every grant. APIs stay enabled. A dataset created
here is deleted only while empty; once it holds export tables destroy stops
on it, so run
`terraform state rm 'module.xplorr.google_bigquery_dataset.billing_export[0]'`
first to keep it.

**gcloud:** remove the grants, then the service account (deleting the
service account also deletes its keys and ends all access at once):

```bash
PROJECT_ID=my-project-id
SA=xplorr-reader@${PROJECT_ID}.iam.gserviceaccount.com

for ROLE in roles/bigquery.jobUser roles/recommender.viewer roles/cloudasset.viewer \
            roles/compute.viewer roles/logging.viewer roles/storage.bucketViewer \
            roles/bigquery.dataViewer; do
  gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" --role="$ROLE" --condition=None --quiet || true
done

# Only if you passed --billing-account
gcloud billing accounts remove-iam-policy-binding 000000-000000-000000 \
  --member="serviceAccount:${SA}" --role=roles/billing.viewer

# Only if you passed --enable-org-level-grants with --organization (repeat per role,
# and use gcloud resource-manager folders remove-iam-policy-binding for folders)
gcloud organizations remove-iam-policy-binding 000000000000 \
  --member="serviceAccount:${SA}" --role=roles/recommender.viewer --condition=None

gcloud iam service-accounts delete "$SA" --project="$PROJECT_ID" --quiet
```

The dataset access entry (`READER` for the service account) goes away with
the service account; edit the dataset's sharing settings in BigQuery if you
want the entry removed from the list too. Delete the local key and
credentials files.

## Troubleshooting

**"GCP permission denied" on Test connection.** BigQuery Data Viewer (on the
dataset) or BigQuery Job User (on the project) is missing, or the grant has
not propagated. Wait a few minutes and try again.

**"Not found: Dataset" or "Not found: Table".** Check, in order:
`bigqueryLocation` matches the dataset's location (`bq show --format=prettyjson my-project-id:billing_export`);
the project, dataset and table names are right; the export has created its
first table (`bq ls my-project-id:billing_export`).

**Terraform plan fails reading `data.google_bigquery_dataset.existing`.** The
dataset does not exist yet. Create it (set `create_billing_dataset = true`)
or fix `billing_dataset_id`.

**Key creation fails with a constraint violation.** Your organization
enforces `iam.disableServiceAccountKeyCreation`. Ask for an exception on this
project; keyless onboarding (coming soon) will not need one.

**`organization_id is set but enable_org_level_grants is false`.** Organization
and folder grants are opt in; see
[Organization and folder grants](#organization-and-folder-grants).

**Active, costs arrive, but no recommendations.** Recommender Viewer is
missing, or the Recommender API is not enabled, or the recommendations live
in regions outside the `regions` credential field (see the field table
above; by default us-central1, us-east1 and europe-west1).

**Active, but inventory is thin.** Cloud Asset Viewer is missing, or the
Cloud Asset API is not enabled, so only the Compute Engine and Cloud Storage
fallback ran.

**`jq: command not found`.** Install jq, or use `gcloud.sh`, which builds the
file with python3 when the key file exists.
