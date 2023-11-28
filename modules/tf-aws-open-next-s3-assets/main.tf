locals {
  assets_folder     = "${var.folder_path}/assets"
  asset_key_prefix  = join("/", compact([var.s3_path_prefix, "assets", var.zone_suffix]))
  origin_asset_path = join("/", compact([var.s3_path_prefix, "assets"]))
  assets = [for file in toset([for file in fileset(local.assets_folder, "**") : file if var.s3_exclusion_regex != null ? length(regexall(var.s3_exclusion_regex, file)) == 0 : true]) : {
    file          = file
    key           = "${local.asset_key_prefix}/${file}"
    source        = "${local.assets_folder}/${file}"
    path_parts    = split("/", file)
    cache_control = length(regexall(var.cache_control_immutable_assets_regex, file)) > 0 ? "public,max-age=31536000,immutable" : "public,max-age=0,s-maxage=31536000,must-revalidate"
    md5           = filemd5("${local.assets_folder}/${file}")
  }]

  cache_folder     = "${var.folder_path}/cache"
  cache_key_prefix = join("/", compact([var.s3_path_prefix, "cache", var.zone_suffix]))
  cache_assets = [for file in toset([for file in fileset(local.cache_folder, "**") : file if var.s3_exclusion_regex != null ? length(regexall(var.s3_exclusion_regex, file)) == 0 : true]) : {
    file   = file
    key    = "${local.cache_key_prefix}/${file}"
    source = "${local.cache_folder}/${file}"
    md5    = filemd5("${local.cache_folder}/${file}")
  }]

  additional_files = [for file in var.additional_files : {
    file   = file.name
    key    = join("/", [var.s3_path_prefix, "custom", file.path_prefix, file.name])
    source = file.source
    md5    = filemd5(file.source)
  }]
}

resource "terraform_data" "remove_folder" {
  count = var.remove_folder ? 1 : 0

  triggers_replace = [var.s3_path_prefix, file("${local.assets_folder}/BUILD_ID")]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/delete-folder.sh"

    environment = {
      "BUCKET_NAME" = var.bucket_name
      "FOLDER"      = local.asset_key_prefix
    }
  }
}

resource "terraform_data" "file_sync" {
  for_each = merge({
    for asset in local.assets : asset.file => asset
    }, {
    for cache in local.cache_assets : cache.file => cache
    }, {
    for additional_file in local.additional_files : additional_file.file => additional_file
  })

  triggers_replace = [var.zone_suffix, var.s3_path_prefix, each.value.md5]

  provisioner "local-exec" {
    command = "/bin/bash ${path.module}/scripts/sync-file.sh"

    environment = {
      "BUCKET_NAME"   = var.bucket_name
      "KEY"           = each.value.key
      "SOURCE"        = each.value.source
      "CACHE_CONTROL" = try(each.value.cache_control, null)
      "CONTENT_TYPE"  = lookup(var.content_types.mapping, reverse(split(".", each.value.file))[0], var.content_types.default)
    }
  }

  depends_on = [terraform_data.remove_folder]
}