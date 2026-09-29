# Opt-in write access (off unless you apply this folder). Creates only the
# separate xplorr-write role, for an account whose read-only role exists
# already; the read-only role is not changed. Xplorr uses it only after a
# person in your Xplorr organization approves an action.
#
# customer_principal: trust the same IAM user as the read-only role, and let
# that user assume this role (user_assumable_role_arns where it is created, or
# enable_write_role in single-account instead of this folder).
# xplorr_principal: set trust_mode, clear trusted_principal_arns, and paste the
# write access external ID Xplorr shows you.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = include.root.locals.write_module_source
}

inputs = {
  # Only the action types you list are granted: stop_idle_instance,
  # delete_unattached_ebs_volume, release_unassociated_eip.
  actions                = ["stop_idle_instance"]
  trust_mode             = "customer_principal"
  role_name              = "xplorr-write"
  trusted_principal_arns = ["arn:aws:iam::111111111111:user/xplorr-assumer"]
  # Its own external ID, never the read-only role's: openssl rand -hex 16
  iam_external_id = ""
  # Resources tagged xplorr:protect = true are refused. "" turns this off.
  protect_tag_key = "xplorr:protect"
  allowed_regions = []
}
