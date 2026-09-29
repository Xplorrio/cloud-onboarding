# xplorr_principal trust mode. REQUIRES XPLORR KEYLESS ONBOARDING (COMING
# SOON). The role trusts Xplorr roles named xplorr-* in Xplorr's AWS account,
# with the external ID Xplorr generates for your organization; no IAM user or
# access key is created.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = include.root.locals.module_source
}

inputs = {
  trust_mode        = "xplorr_principal"
  xplorr_account_id = "732121667940"
  iam_external_id   = "the-value-xplorr-shows-you"
  region            = include.root.locals.region

  # Opt-in write access, off by default: a separate xplorr-write role for the
  # action types you list, with the write access external ID Xplorr shows you.
  enable_write_role     = false
  write_actions         = ["stop_idle_instance"]
  write_iam_external_id = "the-write-value-xplorr-shows-you"
}
