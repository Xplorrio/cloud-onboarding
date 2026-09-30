# One account, customer_principal trust mode (works today).

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = include.root.locals.module_source
}

inputs = {
  trust_mode = "customer_principal"
  role_name  = "xplorr-readonly"
  # Optional. Leave empty for no external ID, or paste a value from: openssl rand -hex 16
  iam_external_id        = ""
  region                 = include.root.locals.region
  attach_readonly_access = false
}
