# Connect Azure to Xplorr

Infrastructure code that creates exactly the Azure identity and read-only
roles Xplorr needs, and prints exactly what the Xplorr **Connect account**
form asks for: `tenantId`, `clientId`, `clientSecret` and `subscriptionId`.

Pick one tool:

| | Terraform (`terraform/`) | Bicep (`bicep/`) |
|---|---|---|
| Creates the app registration and service principal | Yes (CloudDrove [`terraform-az-modules/service-principle`](https://registry.terraform.io/modules/terraform-az-modules/service-principle/azurerm) module) | Yes (Microsoft Graph Bicep extension, GA since v1.0.0) |
| Roles on a subscription | `examples/subscription` | `main.bicep` |
| Roles on a management group | `examples/management-group` | `management-group.bicep` |
| Carbon Optimization Reader | `enable_carbon_optimization_reader` | `enableCarbonOptimizationReader` |
| Reservations Reader, Savings plan reader (tenant scope) | `enable_reservations_reader` (by built-in id); `enable_savings_plan_reader` (off by default, looked up by name; the az command below is the preferred path) | az CLI step below |
| Storage Blob Data Reader for a FOCUS export | `focus_export_scopes` | az CLI step below |
| Client secret | Not created by default; opt in with `create_client_secret` | Never created |
| Billing roles (credits, invoices) | Guidance below | Guidance below |

Everything granted is read only. Xplorr needs read only access and never
changes resources in your tenant or subscriptions.

## What it creates

One Xplorr cloud account is one Azure subscription.

**The identity** (trust mode `customer_principal`, the default): a single
tenant app registration named `xplorr-reader` and its service principal, in
your tenant.

**Roles on each subscription**, or once on a management group above them:

| Role | Default | What Xplorr reads with it |
|---|---|---|
| Reader | Yes | The connect check (subscription read), resource inventory, VM, App Service and AKS running state, Advisor recommendations, and the Activity Log. Xplorr reads the Activity Log on each sync today to record whether audit log access works (as it does with CloudTrail on AWS), and will use it for anomaly root cause analysis |
| Cost Management Reader | Yes | Daily, network and per-resource costs (Cost Management query). Reader covers these too; it is kept because many policies require it |
| Monitoring Reader | No | The alternative to Reader for the Activity Log, when your policy allows only Cost Management Reader plus Monitoring Reader. Without Reader the inventory stays empty |
| Carbon Optimization Reader | No | Carbon emissions reports (`Microsoft.Carbon`) |

**Optional roles outside the subscription:**

| Role | Scope | What Xplorr reads with it |
|---|---|---|
| Reservations Reader | Tenant, `/providers/Microsoft.Capacity` | Reservations and how much of each is used (Commitments) |
| Savings plan reader | Tenant, `/providers/Microsoft.BillingBenefits` | Savings plans (Commitments) |
| Storage Blob Data Reader | The storage account or container of a FOCUS export | FOCUS export ingestion, if you use it |
| A billing role | Billing account or billing profile | Credits and invoices (see [Billing roles](#billing-roles-for-credits-and-invoices)) |

Reservations and savings plans are tenant level resources: a subscription or
management group role does not reach them. Assigning at tenant scope needs
User Access Administrator there, which usually means a Global Administrator
with [elevated access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin).

## Trust modes

One variable, `trust_mode` (Bicep: `trustMode`):

- **`customer_principal`** (default, works today). The app registration and
  service principal live in your tenant. You create the client secret and
  paste it into Xplorr. The code does not create the secret by default, so it
  never lands in Terraform state or a deployment history.
- **`xplorr_principal`** (coming soon, needs Xplorr keyless onboarding). No
  app registration of yours and no secret of yours. The roles go to the
  service principal of Xplorr's multi-tenant app, which the code provisions in
  your tenant from its application (client) ID, the same as an administrator
  consenting to the app. Xplorr requests no Microsoft Graph permissions, so the
  roles are all the access it gets. Xplorr gives you the application ID when
  keyless onboarding is live; there is no default. Until then the Connect
  account form still needs a client secret, so use `customer_principal`.

## Before you start

Tools:

- Azure CLI 2.60 or later (`az login` as the person creating the access), and
  `jq` for the output commands below.
- For Terraform: Terraform 1.10 or later.
- For Bicep: the Bicep CLI 0.36.1 or later (the Microsoft Graph extension
  needs it; the templates are tested with 0.47.16). `az bicep install` gets
  the latest.

Permissions for the person running it:

- **Xplorr:** the member or admin role.
- **Microsoft Entra ID:** permission to create app registrations (the
  Application Developer role, or the default user setting that allows it).
  For `xplorr_principal`, Cloud Application Administrator or Application
  Administrator.
- **Azure:** Owner, User Access Administrator or Role Based Access Control
  Administrator on the subscription or management group.
- **Cost visibility on:** Enterprise Agreement, the **Account owners can view
  charges** policy; Microsoft Customer Agreement, the billing profile's
  **Azure charges** policy.

## Terraform

Terraform 1.10 or later, with `hashicorp/azurerm` 5.x, `hashicorp/azuread`
3.x and `hashicorp/time` 0.x (the module constrains each to its current major
version; tested with azurerm 5.7.0, azuread 3.10.0 and time 0.14.2). Sign in
first with `az login`.

In `customer_principal` mode the app registration and service principal are
created by the CloudDrove
[`terraform-az-modules/service-principle`](https://github.com/terraform-az-modules/terraform-azurerm-service-principle)
module, pinned to 1.0.0, with everything Xplorr does not need switched off: no
Microsoft Graph API permissions, no app roles, no redirect or logout URLs,
no secret unless you opt in, and none of its single role assignment. Xplorr's
roles (every subscription or the management group, the tenant scope roles and
FOCUS storage) are `azurerm_role_assignment` resources in this module, since
the upstream module assigns only one role at one scope. The app registration
has one owner, `owner_object_id`, which defaults to whoever runs Terraform.
`xplorr_principal` mode does not use the upstream module: it reuses the service
principal of Xplorr's existing multi-tenant app.

```bash
cd azure/terraform/examples/subscription      # or examples/management-group
cp terraform.tfvars.example terraform.tfvars  # replace the placeholders
terraform init
terraform apply
terraform output -raw next_steps
```

Print the Credentials (JSON) for each subscription as clean JSON, ready to
paste once you put the secret in place:

```bash
terraform output -json xplorr_connect_form \
  | jq -r 'to_entries[] | "Azure subscription ID: \(.key)", (.value.credentials_json | fromjson), ""'
```

To use the module from your own code, point `source` at a cloned copy of this
repository:

```hcl
module "xplorr" {
  source = "./cloud-onboarding/azure/terraform" # path to your clone

  subscription_ids = ["00000000-0000-0000-0000-000000000000"]
  # management_group_id = "mg-example"
}
```

or at a release tag:

```hcl
module "xplorr" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//azure/terraform?ref=v0.0.1"

  subscription_ids = ["00000000-0000-0000-0000-000000000000"]
}
```

The module declares no provider blocks; configure `azurerm` (with a
`subscription_id`), `azuread` and `time` in the caller, as the examples do.

### Letting Terraform create the secret (not recommended)

`create_client_secret = true` creates the secret with Terraform and adds a
sensitive `credentials_json_with_secret` output. The secret value is then
stored **in plain text in the Terraform state**, and every plan prints a
warning saying so. Only use it with an encrypted, access controlled backend.

The upstream module also rotates the secret every 180 days: the first
`terraform apply` after that creates a new secret and deletes the old one, and
Xplorr keeps using the old one until you update the account, so its sync
fails. `client_secret_duration` (default `17520h`) sets how long each secret
is valid.

## Bicep

Bicep 0.36.1 or later (the Microsoft Graph extension needs it).
`bicepconfig.json` pins the extension, so run the commands from `azure/bicep`.

```bash
cd azure/bicep
az login

# One subscription
az account set --subscription 00000000-0000-0000-0000-000000000000
az deployment sub create --location westeurope \
  --template-file main.bicep --parameters main.example.bicepparam

# Many subscriptions under a management group
az deployment mg create --management-group-id mg-example --location westeurope \
  --template-file management-group.bicep --parameters management-group.example.bicepparam
```

The deployment outputs `tenantId`, `clientId`, `subscriptionId` (or one entry
per subscription in `connectForms`), `servicePrincipalObjectId` and the
`credentialsJson` to paste, with a placeholder for the secret. As clean JSON:

```bash
# Subscription scope
az deployment sub show --name main --query properties.outputs.credentialsJson.value -o tsv | jq .

# Management group scope
az deployment mg show --management-group-id mg-example --name management-group \
  --query properties.outputs.connectForms.value -o json \
  | jq -r '.[] | "Azure subscription ID: \(.subscriptionId)", (.credentialsJson | fromjson), ""'
```

(`az deployment ... create` names the deployment after the template file
unless you pass `--name`.)

**What Bicep does not assign.** The templates assign only the roles on the
subscription or management group. They do not assign the tenant scope roles
(Reservations Reader, Savings plan reader) or Storage Blob Data Reader for a
FOCUS export; use the az CLI commands under "Tenant scope and FOCUS roles"
below. The Terraform module can assign all of them.

If `trustMode` is `xplorr_principal` without `xplorrApplicationId`, or
`existingPrincipalObjectId` is set without `existingClientId`, the deployment
fails at the start with a message saying which parameter is missing.

Bicep cannot create a client secret, and one should not sit in a deployment's
history anyway. Create it after the deployment (see below).

**Without the Graph extension.** If the deploying identity cannot use the
Graph extension, create the principal with the az CLI and pass it in; the
template then deploys only the role assignments:

```bash
APP_ID=$(az ad app create --display-name xplorr-reader --sign-in-audience AzureADMyOrg --query appId -o tsv)
SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

az deployment sub create --location westeurope --template-file main.bicep \
  --parameters existingPrincipalObjectId="$SP_OBJECT_ID" existingClientId="$APP_ID"
```

**Tenant scope and FOCUS roles.** The Bicep templates do not assign these,
because they sit outside the subscription or management group. With the service principal's
object ID from the outputs:

```bash
SP_OBJECT_ID=<servicePrincipalObjectId output>

# Reservations and savings plans (needs elevated access)
# Reservations Reader by its built-in id, 582fc458-8989-419f-a480-75249bc5db7e
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role 582fc458-8989-419f-a480-75249bc5db7e --scope /providers/Microsoft.Capacity
# Savings plan reader has no id on the built-in roles page; assign it by name
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Savings plan reader" --scope /providers/Microsoft.BillingBenefits

# FOCUS export storage account
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample
```

## Create the client secret

Portal: **Microsoft Entra ID > App registrations > xplorr-reader >
Certificates & secrets > Client secrets > New client secret**. Pick an
expiry, click **Add**, and copy the **Value** (not the Secret ID) straight
away; Azure shows it once.

Or with the az CLI, which prints it once to your terminal and stores it
nowhere else:

```bash
az ad app credential reset --id <clientId> --append --display-name xplorr --years 2 --query password -o tsv
```

Pick a long expiry and keep a reminder: an expired secret stops the sync.

## Rotating the client secret

1. Create a new secret next to the old one (portal, or
   `az ad app credential reset --id <clientId> --append --display-name xplorr --years 2 --query password -o tsv`).
   `--append` keeps the old secret working meanwhile.
2. In Xplorr go to **Infrastructure > Cloud Accounts**, and on the account's
   row choose **Update credentials**. Paste the Credentials (JSON) with the new
   secret. The tenant, client and subscription IDs stay as stored.
3. Once the next sync succeeds, delete the old secret: **App registrations >
   xplorr-reader > Certificates & secrets**, or
   `az ad app credential delete --id <clientId> --key-id <old secret key ID>`
   (`az ad app credential list --id <clientId>` lists the key IDs).

With `create_client_secret = true`, Terraform owns the secret instead: run
`terraform apply` to rotate it, then update the account in Xplorr with the new
value from `terraform output -json credentials_json_with_secret`.

## What to paste into Xplorr

In Xplorr go to **Infrastructure > Cloud Accounts > Connect account** and set
**Provider** to **Microsoft Azure**. For each subscription:

- **Account name:** anything you like.
- **Azure subscription ID:** the subscription ID.
- **Credentials (JSON):** the `credentials_json` from `xplorr_connect_form`
  (Bicep: `credentialsJson`), with the secret in place:

  ```json
  {
    "clientId": "00000000-0000-0000-0000-000000000000",
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "clientSecret": "your-client-secret-value",
    "subscriptionId": "00000000-0000-0000-0000-000000000000"
  }
  ```

  All four keys are required, and `subscriptionId` in the JSON is the one
  Xplorr queries, so it must match the subscription ID field.

Click **Test connection**, then **Connect account**. Role assignments can take
a few minutes to apply; if the test says the principal cannot read the
subscription, wait and try again.

## Billing roles for credits and invoices

Credits (balances, credit lots, consumption commitments) and invoices are read
from your billing account, which no subscription or management group role
reaches. No Terraform resource in `azurerm` or `azuread` and no Bicep resource
manages billing role assignments, so these are manual steps. Use the service
principal **object ID** (`service_principal_object_id` /
`servicePrincipalObjectId`), which is the Enterprise application object ID,
not the app registration's object ID.

| Agreement | What Xplorr reads | Role | Scope |
|---|---|---|---|
| Microsoft Customer Agreement | Credit balance and credit lots | Billing profile reader | Billing profile |
| Microsoft Customer Agreement | Consumption commitment (MACC) lots, invoices | Billing account reader (or Invoice manager on the billing profile, for invoices) | Billing account |
| Enterprise Agreement | Azure Prepayment balance, commitment lots, invoices | EnrollmentReader | Enrollment (billing account) |

### Microsoft Customer Agreement

Assign in the portal (**Cost Management + Billing > Billing profiles** or the
billing account **> Access control (IAM) > Add**), or through the
[Billing Role Assignments API](https://learn.microsoft.com/rest/api/billing/billing-role-assignments?view=rest-billing-2024-04-01).
You need Billing profile owner (or Billing account owner) to do this.

```bash
BILLING_ACCOUNT=<billing account ID>
BILLING_PROFILE=<billing profile ID>
TENANT_ID=<tenantId output>
SP_OBJECT_ID=<service principal object ID>
BASE="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$BILLING_ACCOUNT/billingProfiles/$BILLING_PROFILE"

ROLE_ID=$(az rest --method get --url "$BASE/billingRoleDefinitions?api-version=2024-04-01" \
  --query "value[?properties.roleName=='Billing profile reader'].id | [0]" -o tsv)

az rest --method post --url "$BASE/createBillingRoleAssignment?api-version=2024-04-01" \
  --body "{\"principalId\":\"$SP_OBJECT_ID\",\"principalTenantId\":\"$TENANT_ID\",\"roleDefinitionId\":\"$ROLE_ID\"}"
```

For Billing account reader, use the billing account URL (without
`/billingProfiles/...`) and the role name `Billing account reader`.

### Enterprise Agreement

EA roles can be given to a service principal only through the API, and only by
someone with the enrollment writer role (Enterprise Administrator). Follow
[Assign Enterprise Agreement roles to service principals](https://learn.microsoft.com/azure/cost-management-billing/manage/assign-roles-azure-service-principals)
and take the EnrollmentReader role definition ID from the table on that page:

```bash
BILLING_ACCOUNT=<EA billing account (enrollment) ID>
ENROLLMENT_READER_ID=<EnrollmentReader role definition ID from the Microsoft Learn table>

az rest --method put \
  --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$BILLING_ACCOUNT/billingRoleAssignments/$(uuidgen | tr 'A-Z' 'a-z')?api-version=2019-10-01-preview" \
  --body "{\"properties\":{\"principalId\":\"$SP_OBJECT_ID\",\"principalTenantId\":\"$TENANT_ID\",\"roleDefinitionId\":\"/providers/Microsoft.Billing/billingAccounts/$BILLING_ACCOUNT/billingRoleDefinitions/$ENROLLMENT_READER_ID\"}}"
```

A service principal holds one EA role, and EA service principal assignments
do not show in the portal.

Then enter the Azure billing account ID in Xplorr: on the **Credits** page
when you add a credit grant (plus the billing profile ID for MCA), and on the
**Invoices** page for invoice ingestion.

## Removing everything

First delete the cloud accounts in Xplorr (**Infrastructure > Cloud Accounts**,
delete on each row) so the sync stops cleanly. Then:

**Terraform**

```bash
cd azure/terraform/examples/subscription   # the folder you applied from
terraform destroy
```

This deletes the role assignments, the service principal and the app
registration (in `xplorr_principal` mode, the role assignments and Xplorr's
service principal in your tenant).

**Bicep** (a deployment does not delete what it created):

```bash
CLIENT_ID=<clientId output>
SP_OBJECT_ID=<servicePrincipalObjectId output>

# Role assignments on the subscription, or on the management group
az role assignment delete --assignee "$SP_OBJECT_ID" --scope /subscriptions/00000000-0000-0000-0000-000000000000
az role assignment delete --assignee "$SP_OBJECT_ID" --scope /providers/Microsoft.Management/managementGroups/mg-example

# Any tenant scope or FOCUS roles you added by hand
az role assignment delete --assignee "$SP_OBJECT_ID" --scope /providers/Microsoft.Capacity
az role assignment delete --assignee "$SP_OBJECT_ID" --scope /providers/Microsoft.BillingBenefits

# The app registration, which also deletes its service principal and secrets
az ad app delete --id "$CLIENT_ID"
```

In `xplorr_principal` mode, delete Xplorr's service principal instead of an
app registration: `az ad sp delete --id "$SP_OBJECT_ID"`.

Billing role assignments are deleted through the same portal page or API you
created them with.

## Troubleshooting

**"The Azure service principal signed in but cannot read the subscription"**
No role on the subscription yet, or it has not propagated. Role assignments
can take a few minutes; wait and test again. Check with
`az role assignment list --assignee <servicePrincipalObjectId> --all -o table`.

**"Azure authentication failed"** The client ID or tenant ID is wrong, the
secret is the Secret ID rather than the Value, or it has expired. Create a new
secret and use **Update credentials**.

**"That Azure subscription was not found in this tenant"** The
`subscriptionId` or `tenantId` in the JSON is wrong, or the subscription
belongs to another tenant.

**The account is Active but the inventory is empty** The principal has Cost
Management Reader but not Reader. Keep Reader in `role_names`.

**Cost queries fail with a permission error although the role is right**
The agreement's cost visibility policy is off (see Before you start).

**`AuthorizationFailed` on apply, at tenant scope** Assigning Reservations
Reader or Savings plan reader needs User Access Administrator at the root
scope. A Global Administrator can turn on elevated access, run the apply, and
turn it off again.

**`Insufficient privileges to complete the operation` when creating the app**
The person running it cannot create app registrations. Ask for the
Application Developer role, or have an administrator create the app and
service principal and use Bicep's `existingPrincipalObjectId`.

**Bicep: `The extension microsoftGraphV1 could not be restored`** Run the
commands from `azure/bicep`, where `bicepconfig.json` pins the extension, and
upgrade the Bicep CLI with `az bicep upgrade`.

## Files

```
azure/
  terraform/                  module: versions.tf, variables.tf, main.tf, outputs.tf
                              (app registration via terraform-az-modules/service-principle)
    tests/module.tftest.hcl   plan only tests with mocked providers
    examples/subscription/
    examples/management-group/
  bicep/
    bicepconfig.json          pins the Microsoft Graph Bicep extension
    main.bicep                subscription scope
    management-group.bicep    management group scope
    modules/                  the role assignments, one module per scope
    *.example.bicepparam
```
