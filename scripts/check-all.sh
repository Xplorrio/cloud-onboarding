#!/usr/bin/env bash
# Run every repository check locally, the same ones CI runs.
#
# Needs: terraform, tflint, terragrunt, cfn-lint, bicep, shellcheck, gitleaks,
# python3, and CLIENT_DATA_HMAC_KEY exported (see CONTRIBUTING.md).
# Nothing here talks to a cloud account: Terraform tests plan against fake
# credentials and mocked providers.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

failed=()

run() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if "$@"; then
    printf 'ok: %s\n' "$name"
  else
    printf 'FAILED: %s\n' "$name"
    failed+=("$name")
  fi
}

need() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'missing tool: %s\n' "$tool"
      exit 1
    fi
  done
}

terraform_roots() {
  find aws azure gcp -name '*.tf' -not -path '*/.terraform/*' -not -path '*/.terragrunt-cache/*' \
    -exec dirname {} \; | sort -u
}

check_terraform_root() {
  local dir="$1" config
  config="$PWD/${dir%%/*}/terraform/.tflint.hcl"
  (
    cd "$dir" &&
      terraform init -backend=false -input=false -no-color >/dev/null &&
      terraform validate -no-color &&
      { [ ! -d tests ] || terraform test -no-color; } &&
      tflint --init --config="$config" >/dev/null &&
      tflint --config="$config" --format compact
  )
}

check_terragrunt() {
  (
    cd aws/terragrunt &&
      terragrunt hcl fmt --check &&
      terragrunt hcl validate &&
      (cd single-account && env -u XPLORR_MODULE_SOURCE terragrunt validate --non-interactive) &&
      (cd keyless && env -u XPLORR_MODULE_SOURCE terragrunt validate --non-interactive)
  )
}

check_bicep() {
  local out f
  out="$(mktemp -d)"
  while IFS= read -r f; do
    bicep lint "$f" && bicep build "$f" --outdir "$out" || return 1
  done < <(find azure -name '*.bicep')
  while IFS= read -r f; do
    bicep build-params "$f" --outfile "$out/$(basename "$f").json" || return 1
  done < <(find azure -name '*.bicepparam')
}

check_shell() {
  git ls-files -z '*.sh' | xargs -0 shellcheck
}

need terraform tflint terragrunt cfn-lint bicep shellcheck gitleaks python3

run "terraform fmt" terraform fmt -check -recursive
while IFS= read -r dir; do
  run "terraform $dir" check_terraform_root "$dir"
done < <(terraform_roots)
run "terragrunt" check_terragrunt
run "cfn-lint" cfn-lint aws/cloudformation/role.yaml aws/cloudformation/stackset.yaml
run "stackset embeds role.yaml" python3 scripts/sync-stackset.py --check
run "AWS policy drift" python3 scripts/check-policy-drift.py
run "bicep" check_bicep
run "shellcheck" check_shell
run "gitleaks (history)" gitleaks git --redact --no-banner .
run "gitleaks (working tree)" gitleaks dir --redact --no-banner .
run "client data" python3 scripts/check-client-data.py
run "client data tests" python3 scripts/test-check-client-data.py
run "style" python3 scripts/check-style.py

printf '\n'
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'Failed checks:\n'
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
printf 'All checks passed.\n'
