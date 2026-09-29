#!/usr/bin/env bash
#
# Creates the Google Cloud identity Xplorr reads with, and prints what to
# paste into the Xplorr Connect account form. It does the same as the
# Terraform module in gcp/terraform, with gcloud and bq.
#
# Safe to re-run: every step checks what exists first, IAM bindings are only
# added, and a key is created only on request and never twice.
#
# Usage:
#   ./gcloud.sh --project my-project-id [options]
#
# Options:
#   --project ID              Project that holds the billing export (required)
#   --dataset NAME            Billing export dataset (default billing_export)
#   --location LOC            Dataset location, used to create it (default US).
#                             An existing dataset's own location always wins.
#   --create-dataset          Create the dataset if it does not exist
#   --table NAME              Standard export table, if you want to pin it
#   --bigquery-scope SCOPE    dataset (default) or project, for Data Viewer
#   --extra-dataset NAME      Another dataset Xplorr may read (repeatable)
#   --billing-account ID      Grant Billing Account Viewer on it
#   --enable-org-level-grants Allow --organization and --folder (off by default).
#                             Xplorr currently reads only the connected project,
#                             so these grants give it nothing today.
#   --organization ID         Also grant the read roles on the organization
#                             (needs --enable-org-level-grants)
#   --folder ID               Also grant the read roles on a folder, repeatable
#                             (needs --enable-org-level-grants)
#   --service-account NAME    Service account id (default xplorr-reader)
#   --trust-mode MODE         customer_principal (default) or xplorr_principal
#                             (coming soon, not live in Xplorr yet)
#   --xplorr-principal EMAIL  Xplorr's service account, for xplorr_principal
#   --create-key              Create a JSON key file (customer_principal only)
#   --key-file PATH           Where the key file is, or where --create-key writes it
#                             (default ./xplorr-key.json)
#   --output-dir DIR          Where xplorr-connect-form.json and
#                             xplorr-credentials.json are written (default .)
#   --skip-apis               Do not enable APIs
#   --enable-write-action A   Opt-in write access: create a separate custom role
#                             for approved action type A and grant it to the
#                             service account (repeatable). Off unless given.
#                             Action types: stop_idle_instance
#   --write-role-id ID        Custom role id for write access (default xplorrWrite)
#   --write-protect-tag KEY   Refuse instances tagged KEY=true, for example
#                             my-project-id/xplorr-protect (a Resource Manager
#                             tag key that already exists, with value true)
#   -h, --help                Show this help
#
# Needs: gcloud, bq (part of the Google Cloud SDK) and python3.

set -euo pipefail

PROJECT_ID=""
DATASET="billing_export"
LOCATION="US"
CREATE_DATASET="false"
TABLE=""
BQ_SCOPE="dataset"
EXTRA_DATASETS=()
BILLING_ACCOUNT=""
ORGANIZATION=""
FOLDERS=()
ORG_GRANTS="false"
OUTPUT_DIR="."
SA_ID="xplorr-reader"
TRUST_MODE="customer_principal"
XPLORR_PRINCIPAL=""
CREATE_KEY="false"
KEY_FILE="./xplorr-key.json"
ENABLE_APIS="true"
WRITE_ACTIONS=()
WRITE_ROLE_ID="xplorrWrite"
WRITE_PROTECT_TAG=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) need_value "$@"; PROJECT_ID="$2"; shift 2 ;;
    --dataset) need_value "$@"; DATASET="$2"; shift 2 ;;
    --location) need_value "$@"; LOCATION="$2"; shift 2 ;;
    --create-dataset) CREATE_DATASET="true"; shift ;;
    --table) need_value "$@"; TABLE="$2"; shift 2 ;;
    --bigquery-scope) need_value "$@"; BQ_SCOPE="$2"; shift 2 ;;
    --extra-dataset) need_value "$@"; EXTRA_DATASETS+=("$2"); shift 2 ;;
    --billing-account) need_value "$@"; BILLING_ACCOUNT="$2"; shift 2 ;;
    --enable-org-level-grants) ORG_GRANTS="true"; shift ;;
    --organization) need_value "$@"; ORGANIZATION="$2"; shift 2 ;;
    --folder) need_value "$@"; FOLDERS+=("$2"); shift 2 ;;
    --service-account) need_value "$@"; SA_ID="$2"; shift 2 ;;
    --trust-mode) need_value "$@"; TRUST_MODE="$2"; shift 2 ;;
    --xplorr-principal) need_value "$@"; XPLORR_PRINCIPAL="$2"; shift 2 ;;
    --create-key) CREATE_KEY="true"; shift ;;
    --key-file) need_value "$@"; KEY_FILE="$2"; shift 2 ;;
    --output-dir) need_value "$@"; OUTPUT_DIR="$2"; shift 2 ;;
    --skip-apis) ENABLE_APIS="false"; shift ;;
    --enable-write-action) need_value "$@"; WRITE_ACTIONS+=("$2"); shift 2 ;;
    --write-role-id) need_value "$@"; WRITE_ROLE_ID="$2"; shift 2 ;;
    --write-protect-tag) need_value "$@"; WRITE_PROTECT_TAG="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

# Input checks

[[ -n "$PROJECT_ID" ]] || die "--project is required"
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "--project must be a project id, for example my-project-id"
[[ "$DATASET" =~ ^[A-Za-z0-9_]+$ ]] || die "--dataset may hold only letters, digits and underscores"
for d in "${EXTRA_DATASETS[@]+"${EXTRA_DATASETS[@]}"}"; do
  [[ "$d" =~ ^[A-Za-z0-9_]+$ ]] || die "--extra-dataset $d may hold only letters, digits and underscores"
done
[[ -z "$TABLE" || "$TABLE" =~ ^[A-Za-z0-9_*-]+$ ]] || die "--table may hold only letters, digits, underscores, hyphens and *"
[[ "$BQ_SCOPE" == "dataset" || "$BQ_SCOPE" == "project" ]] || die "--bigquery-scope must be dataset or project"
[[ "$SA_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "--service-account must be 6 to 30 lowercase letters, digits or hyphens"
[[ -z "$BILLING_ACCOUNT" || "$BILLING_ACCOUNT" =~ ^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$ ]] || die "--billing-account must look like 000000-000000-000000"
[[ -z "$ORGANIZATION" || "$ORGANIZATION" =~ ^[0-9]+$ ]] || die "--organization must be the numeric organization id"
for f in "${FOLDERS[@]+"${FOLDERS[@]}"}"; do
  [[ "$f" =~ ^[0-9]+$ ]] || die "--folder $f must be a numeric folder id"
done
if [[ "$ORG_GRANTS" == "false" && ( -n "$ORGANIZATION" || ${#FOLDERS[@]} -gt 0 ) ]]; then
  die "--organization and --folder need --enable-org-level-grants. Xplorr currently reads only the connected project, so these grants give it nothing today."
fi
if [[ "$ORG_GRANTS" == "true" && -z "$ORGANIZATION" && ${#FOLDERS[@]} -eq 0 ]]; then
  die "--enable-org-level-grants needs --organization or --folder"
fi
[[ -d "$OUTPUT_DIR" ]] || die "--output-dir $OUTPUT_DIR does not exist"
case "$TRUST_MODE" in
  customer_principal) ;;
  xplorr_principal)
    [[ "$XPLORR_PRINCIPAL" =~ ^[a-z][a-z0-9-]{4,29}@[a-z0-9-]+\.iam\.gserviceaccount\.com$ ]] ||
      die "--trust-mode xplorr_principal needs --xplorr-principal, the service account shown in the Xplorr Connect account form"
    [[ "$CREATE_KEY" == "false" ]] || die "--create-key makes no sense with xplorr_principal, which is keyless"
    ;;
  *) die "--trust-mode must be customer_principal or xplorr_principal" ;;
esac

WRITE_PERMISSIONS=()
for a in "${WRITE_ACTIONS[@]+"${WRITE_ACTIONS[@]}"}"; do
  case "$a" in
    stop_idle_instance) WRITE_PERMISSIONS+=(compute.instances.stop compute.instances.start) ;;
    *) die "--enable-write-action $a is not an action type here. Google Cloud supports: stop_idle_instance" ;;
  esac
done
[[ "$WRITE_ROLE_ID" =~ ^[a-zA-Z0-9_.]{3,64}$ ]] || die "--write-role-id must be 3 to 64 letters, digits, underscores or periods"
if [[ -n "$WRITE_PROTECT_TAG" ]]; then
  [[ ${#WRITE_ACTIONS[@]} -gt 0 ]] || die "--write-protect-tag needs --enable-write-action"
  [[ "$WRITE_PROTECT_TAG" =~ ^[a-z0-9][a-z0-9-]{0,62}/[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]] ||
    die "--write-protect-tag must be a namespaced tag key such as my-project-id/xplorr-protect"
fi

for tool in gcloud bq python3; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed or not on PATH"
done

SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
MEMBER="serviceAccount:${SA_EMAIL}"

PROJECT_ROLES=(
  roles/bigquery.jobUser
  roles/recommender.viewer
  roles/cloudasset.viewer
  roles/compute.viewer
  roles/logging.viewer
  roles/storage.bucketViewer
)
if [[ "$BQ_SCOPE" == "project" ]]; then
  PROJECT_ROLES+=(roles/bigquery.dataViewer)
fi

SCOPE_ROLES=(
  roles/recommender.viewer
  roles/cloudasset.viewer
  roles/compute.viewer
  roles/logging.viewer
  roles/storage.bucketViewer
)

step() {
  echo
  echo "==> $*"
}

# A new service account can take a minute to be visible to IAM, so bindings
# are retried a few times before giving up.
retry() {
  local n=1
  until "$@"; do
    if ((n >= 6)); then
      return 1
    fi
    echo "    not ready yet, retrying in $((n * 5))s" >&2
    sleep $((n * 5))
    n=$((n + 1))
  done
}

gcloud projects describe "$PROJECT_ID" --format='value(projectId)' >/dev/null ||
  die "cannot read project $PROJECT_ID with the current gcloud account"

# 1. APIs. compute.googleapis.com is not enabled here: on a project that never
# used Compute Engine that creates the default network, and without it there
# are no commitments or VMs to read.

if [[ "$ENABLE_APIS" == "true" ]]; then
  APIS=(bigquery.googleapis.com recommender.googleapis.com cloudasset.googleapis.com logging.googleapis.com)
  if [[ -n "$BILLING_ACCOUNT" ]]; then
    APIS+=(billingbudgets.googleapis.com)
  fi
  if [[ "$TRUST_MODE" == "xplorr_principal" ]]; then
    APIS+=(iamcredentials.googleapis.com)
  fi
  step "Enabling APIs: ${APIS[*]}"
  gcloud services enable "${APIS[@]}" --project="$PROJECT_ID"
fi

# 2. Service account

step "Service account $SA_EMAIL"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "    exists"
else
  gcloud iam service-accounts create "$SA_ID" \
    --project="$PROJECT_ID" \
    --display-name="Xplorr reader" \
    --description="Read only access for Xplorr cloud cost management (${TRUST_MODE})."
fi

# 3. Project roles

step "Granting project roles on $PROJECT_ID"
for role in "${PROJECT_ROLES[@]}"; do
  echo "    $role"
  retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$MEMBER" --role="$role" --condition=None --quiet >/dev/null
done

# 4. Billing export dataset, and Data Viewer on it

step "Billing export dataset ${PROJECT_ID}:${DATASET}"
if bq --project_id="$PROJECT_ID" show --format=json "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
  echo "    exists"
elif [[ "$CREATE_DATASET" == "true" ]]; then
  bq --project_id="$PROJECT_ID" mk --dataset --location="$LOCATION" \
    --description="Cloud Billing export to BigQuery, read by Xplorr" "${PROJECT_ID}:${DATASET}"
else
  echo "    does not exist. Create it with --create-dataset, or: bq mk --dataset --location=${LOCATION} ${PROJECT_ID}:${DATASET}"
fi

DATASET_JSON=""
if DATASET_JSON=$(bq --project_id="$PROJECT_ID" show --format=json "${PROJECT_ID}:${DATASET}" 2>/dev/null); then
  ACTUAL_LOCATION=$(printf '%s' "$DATASET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("location",""))')
  if [[ -n "$ACTUAL_LOCATION" && "$ACTUAL_LOCATION" != "$LOCATION" ]]; then
    echo "    the dataset is in $ACTUAL_LOCATION, so bigqueryLocation is $ACTUAL_LOCATION"
    LOCATION="$ACTUAL_LOCATION"
  fi
fi

# Adds a READER entry (the dataset form of roles/bigquery.dataViewer) to a
# dataset's access list, leaving every other entry alone, including the one
# Google adds for its billing export service account.
grant_dataset_reader() {
  local dataset="$1" tmp
  local ref="${PROJECT_ID}:${dataset}"
  if ! bq --project_id="$PROJECT_ID" show --format=json "$ref" >/dev/null 2>&1; then
    echo "    $dataset does not exist yet; re-run this script once it does"
    return 0
  fi
  tmp=$(mktemp)
  bq --project_id="$PROJECT_ID" show --format=json "$ref" >"$tmp"
  local rc=0
  SA_EMAIL="$SA_EMAIL" python3 - "$tmp" <<'PY' || rc=$?
import json, os, sys
path, email = sys.argv[1], os.environ["SA_EMAIL"].lower()
with open(path) as fh:
    ds = json.load(fh)
access = ds.get("access", [])
if any(str(a.get("userByEmail", "")).lower() == email and a.get("role") in ("READER", "roles/bigquery.dataViewer") for a in access):
    sys.exit(3)
access.append({"role": "READER", "userByEmail": email})
with open(path, "w") as fh:
    json.dump({"access": access}, fh)
PY
  case "$rc" in
    0)
      bq --project_id="$PROJECT_ID" update --source "$tmp" "$ref" >/dev/null
      echo "    $dataset: granted"
      ;;
    3) echo "    $dataset: already granted" ;;
    *)
      rm -f "$tmp"
      die "could not read the access list of $ref"
      ;;
  esac
  rm -f "$tmp"
}

if [[ "$BQ_SCOPE" == "dataset" ]]; then
  step "Granting BigQuery Data Viewer on datasets"
  for d in "$DATASET" "${EXTRA_DATASETS[@]+"${EXTRA_DATASETS[@]}"}"; do
    grant_dataset_reader "$d"
  done
fi

# 5. Billing account

if [[ -n "$BILLING_ACCOUNT" ]]; then
  step "Granting Billing Account Viewer on billing account $BILLING_ACCOUNT"
  retry gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
    --member="$MEMBER" --role=roles/billing.viewer --quiet >/dev/null
fi

# 6. Organization and folders, only with --enable-org-level-grants. Xplorr
# currently reads recommendations, inventory and audit logs with
# projects/<id> scope, so these grants give it nothing today.

if [[ -n "$ORGANIZATION" ]]; then
  step "Granting read roles on organization $ORGANIZATION"
  for role in "${SCOPE_ROLES[@]}"; do
    echo "    $role"
    retry gcloud organizations add-iam-policy-binding "$ORGANIZATION" \
      --member="$MEMBER" --role="$role" --condition=None --quiet >/dev/null
  done
fi
for folder in "${FOLDERS[@]+"${FOLDERS[@]}"}"; do
  step "Granting read roles on folder $folder"
  for role in "${SCOPE_ROLES[@]}"; do
    echo "    $role"
    retry gcloud resource-manager folders add-iam-policy-binding "$folder" \
      --member="$MEMBER" --role="$role" --condition=None --quiet >/dev/null
  done
done

# 7. How Xplorr signs in

if [[ "$TRUST_MODE" == "xplorr_principal" ]]; then
  step "Allowing $XPLORR_PRINCIPAL to impersonate $SA_EMAIL (coming soon in Xplorr)"
  retry gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${XPLORR_PRINCIPAL}" \
    --role=roles/iam.serviceAccountTokenCreator --condition=None --quiet >/dev/null
elif [[ "$CREATE_KEY" == "true" ]]; then
  step "Key file $KEY_FILE"
  if [[ -e "$KEY_FILE" ]]; then
    echo "    $KEY_FILE exists, so no new key was created. Delete or move it to create another."
  else
    (umask 077 && gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL" --project="$PROJECT_ID")
  fi
fi

# 8. Opt-in write access, only with --enable-write-action. A separate custom
# role holding only the permissions of the listed action types, granted to
# the same service account. The viewer roles above are not changed. Xplorr
# uses it only after a person in your Xplorr organization approves an action.

if [[ ${#WRITE_ACTIONS[@]} -gt 0 ]]; then
  WRITE_ROLE="projects/${PROJECT_ID}/roles/${WRITE_ROLE_ID}"
  PERMS=$(printf '%s\n' "${WRITE_PERMISSIONS[@]}" | sort -u | paste -sd, -)
  step "Write access: custom role $WRITE_ROLE ($PERMS)"
  ROLE_STATE=$(gcloud iam roles describe "$WRITE_ROLE_ID" --project="$PROJECT_ID" --format='value(deleted)' 2>/dev/null || echo missing)
  if [[ "$ROLE_STATE" == "missing" ]]; then
    gcloud iam roles create "$WRITE_ROLE_ID" --project="$PROJECT_ID" \
      --title="Xplorr write" \
      --description="Opt-in write access for Xplorr approved actions: ${WRITE_ACTIONS[*]}" \
      --permissions="$PERMS" --stage=GA --quiet >/dev/null
    echo "    created"
  else
    if [[ "$ROLE_STATE" == "True" ]]; then
      gcloud iam roles undelete "$WRITE_ROLE_ID" --project="$PROJECT_ID" --quiet >/dev/null
      echo "    undeleted"
    fi
    gcloud iam roles update "$WRITE_ROLE_ID" --project="$PROJECT_ID" \
      --permissions="$PERMS" --quiet >/dev/null
    echo "    permissions set"
  fi

  step "Granting $WRITE_ROLE to $SA_EMAIL on $PROJECT_ID"
  if [[ -n "$WRITE_PROTECT_TAG" ]]; then
    # The expression holds a comma, which --condition cannot take, so the
    # condition goes through a file.
    CONDITION_FILE=$(mktemp)
    WRITE_PROTECT_TAG="$WRITE_PROTECT_TAG" python3 - "$CONDITION_FILE" <<'PY'
import json, os, sys
tag = os.environ["WRITE_PROTECT_TAG"]
with open(sys.argv[1], "w") as fh:
    json.dump({
        "title": "not-protected",
        "description": f"Refuse instances tagged {tag} = true",
        "expression": f"!resource.matchTag('{tag}', 'true')",
    }, fh)
PY
    retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="$MEMBER" --role="$WRITE_ROLE" --condition-from-file="$CONDITION_FILE" --quiet >/dev/null
    rm -f "$CONDITION_FILE"
    echo "    with a condition refusing instances tagged ${WRITE_PROTECT_TAG}=true"
  else
    retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="$MEMBER" --role="$WRITE_ROLE" --condition=None --quiet >/dev/null
  fi
fi

# 9. Find the export table, if the export has started

if [[ -z "$TABLE" ]]; then
  TABLE=$(bq --project_id="$PROJECT_ID" ls --format=json --max_results=1000 "${PROJECT_ID}:${DATASET}" 2>/dev/null |
    python3 -c '
import json, sys
try:
    tables = json.load(sys.stdin)
except ValueError:
    tables = []
names = sorted(t["tableReference"]["tableId"] for t in tables if t["tableReference"]["tableId"].startswith("gcp_billing_export_v1_"))
print(names[0] if len(names) == 1 else "")
' || true)
fi

# 10. What to paste into Xplorr. The non secret fields go to
# xplorr-connect-form.json. The complete Credentials (JSON), key included, is
# written to xplorr-credentials.json only when the key file is present, and is
# never printed.

CONNECT_FILE="${OUTPUT_DIR%/}/xplorr-connect-form.json"
CREDENTIALS_FILE="${OUTPUT_DIR%/}/xplorr-credentials.json"

(umask 077 && PROJECT_ID="$PROJECT_ID" DATASET="$DATASET" TABLE="$TABLE" LOCATION="$LOCATION" BILLING_ACCOUNT="$BILLING_ACCOUNT" python3 - "$CONNECT_FILE" <<'PY'
import json, os, sys
e = os.environ
out = {"projectId": e["PROJECT_ID"], "billingDataset": e["DATASET"]}
if e["TABLE"]:
    out["billingTable"] = e["TABLE"]
out["bigqueryLocation"] = e["LOCATION"]
if e["BILLING_ACCOUNT"]:
    out["billingAccountId"] = e["BILLING_ACCOUNT"]
with open(sys.argv[1], "w") as fh:
    json.dump(out, fh, indent=2)
    fh.write("\n")
PY
)
chmod 600 "$CONNECT_FILE"

echo
echo "================================================================"
echo "Done. Service account: $SA_EMAIL"
echo "================================================================"
if [[ ${#WRITE_ACTIONS[@]} -gt 0 ]]; then
  echo
  echo "Write access (opt in): custom role projects/${PROJECT_ID}/roles/${WRITE_ROLE_ID}"
  echo "  action types: ${WRITE_ACTIONS[*]}"
  echo "  granted to:   $SA_EMAIL${WRITE_PROTECT_TAG:+, except instances tagged ${WRITE_PROTECT_TAG}=true}"
  echo "  Xplorr uses it only after a person in your Xplorr organization approves an action."
fi
if [[ -z "$TABLE" ]]; then
  echo
  echo "No gcp_billing_export_v1_* table found in ${PROJECT_ID}:${DATASET} yet."
  echo "Turn the export on in the console if it is off:"
  echo "  Billing > Billing export > BigQuery export > Standard usage cost"
  echo "  (and Detailed usage cost, for per resource costs), dataset ${PROJECT_ID}:${DATASET}."
  echo "Connect once the first table appears; Xplorr's connect check queries it."
fi

if [[ "$TRUST_MODE" == "xplorr_principal" ]]; then
  echo
  echo "Keyless GCP onboarding is coming soon and is not live in Xplorr yet."
  echo "When it is, give Xplorr: projectId $PROJECT_ID, service account $SA_EMAIL,"
  echo "dataset $DATASET, location $LOCATION (also in $CONNECT_FILE)."
  exit 0
fi

echo
echo "Connect form fields (no secret): $CONNECT_FILE"
if [[ -e "$KEY_FILE" ]]; then
  (umask 077 && python3 - "$CONNECT_FILE" "$KEY_FILE" "$CREDENTIALS_FILE" <<'PY'
import json, sys
connect_path, key_path, out_path = sys.argv[1:4]
with open(connect_path) as fh:
    creds = json.load(fh)
with open(key_path) as fh:
    creds["keyfileJson"] = json.load(fh)
with open(out_path, "w") as fh:
    json.dump(creds, fh, indent=2)
    fh.write("\n")
PY
  )
  chmod 600 "$CREDENTIALS_FILE"
  echo "Credentials (JSON), key included: $CREDENTIALS_FILE (mode 600)"
else
  echo
  echo "Create the key yourself (this script writes one only with --create-key):"
  echo "  gcloud iam service-accounts keys create ${KEY_FILE} --iam-account=${SA_EMAIL} --project=${PROJECT_ID}"
  echo "Then build the Credentials (JSON) file, which merges the key in as keyfileJson:"
  echo "  (umask 077 && jq --slurpfile key ${KEY_FILE} '. + {keyfileJson: \$key[0]}' ${CONNECT_FILE} > ${CREDENTIALS_FILE})"
  echo "or re-run this script with the same options: it builds ${CREDENTIALS_FILE} once ${KEY_FILE} exists."
fi
echo
echo "In Xplorr: Infrastructure > Cloud Accounts > Connect account > Google Cloud Platform"
echo "  GCP project ID:     $PROJECT_ID"
echo "  Credentials (JSON): the contents of $CREDENTIALS_FILE"
echo
echo "Once the account shows Active in Xplorr, delete the local copies of the key:"
echo "  rm -f ${CREDENTIALS_FILE} ${KEY_FILE} ${CONNECT_FILE}"
