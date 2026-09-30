# Shared settings for every Xplorr role this folder creates.
#
# The state holds no secret: Terraform creates no access key. A local backend
# is enough for a one off role; to keep state in S3, uncomment remote_state
# and fill in your own bucket.

locals {
  region = "us-east-1"

  # Where the module comes from. The default is the module in this cloned
  # repository. To use a pinned release instead (works once the repository is
  # public), set:
  #   XPLORR_MODULE_SOURCE="git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.0.1"
  module_source = get_env("XPLORR_MODULE_SOURCE", "${get_parent_terragrunt_dir()}/../terraform")
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
    }
  EOT
}

# remote_state {
#   backend = "s3"
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite_terragrunt"
#   }
#   config = {
#     bucket       = "example-terraform-state"
#     key          = "xplorr/${path_relative_to_include()}/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
