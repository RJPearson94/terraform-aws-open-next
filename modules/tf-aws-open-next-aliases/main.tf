locals {
  prefix = var.prefix == null ? "" : "${var.prefix}-"
  suffix = var.suffix == null ? "" : "-${var.suffix}"

  origin_aliases = jsondecode(data.aws_ssm_parameter.origin_aliases.insecure_value)
  alias_inverse_mappings = {
    "nextjs"   = "opennext",
    "opennext" = "nextjs"
  }

  use_production_alias_when_non_continuous_deployment_strategy = var.continuous_deployment_strategy == "NONE" ? local.origin_aliases.production : null
  use_staging_alias_when_deployment_is_detach_or_promote       = contains(["DETACH", "PROMOTE"], var.continuous_deployment_strategy) ? local.origin_aliases.staging : null
  use_default_alias_when_staging_is_not_set                    = local.origin_aliases.staging == null ? local.alias_inverse_mappings[local.origin_aliases.production] : null
  flip_staging_alias_when_aliases_match                        = local.origin_aliases.production == local.origin_aliases.staging ? local.alias_inverse_mappings[local.origin_aliases.staging] : local.origin_aliases.staging
  alias_details = {
    aliases    = keys(local.alias_inverse_mappings)
    production = local.origin_aliases.production
    staging = var.use_continuous_deployment == false ? local.origin_aliases.production : coalesce(
      local.use_production_alias_when_non_continuous_deployment_strategy,
      local.use_staging_alias_when_deployment_is_detach_or_promote,
      local.use_default_alias_when_staging_is_not_set,
      local.flip_staging_alias_when_aliases_match
    )
  }

  updated_alias_mapping = var.continuous_deployment_strategy == "PROMOTE" ? { production = local.alias_details.staging, staging = local.alias_details.staging } : { production = local.alias_details.production, staging = local.alias_details.staging }
}

# Config

resource "aws_ssm_parameter" "origin_aliases" {
  name  = "${local.prefix}website-origin-aliases${local.suffix}"
  type  = "String"
  value = jsonencode({ production = "nextjs", staging = null })

  lifecycle {
    ignore_changes = [value]
  }
}