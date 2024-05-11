data "aws_region" "current" {}

# Zip Archives

data "archive_file" "server_function" {
  count       = try(var.server_function.function_code.zip, null) == null && try(var.server_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${local.open_next_default_server}.zip"
  source_dir  = local.open_next_default_server

  depends_on = [local_file.lambda_at_edge_modifications]
}

data "archive_file" "additional_server_function" {
  for_each = { for name, additional_server_function in local.additional_server_functions : name => additional_server_function if try(var.additional_server_functions.function_overrides[name].function_code.zip, null) == null && try(var.additional_server_functions.function_overrides[name].function_code.s3, null) == null }
  type        = "zip"
  output_path = "${local.open_next_path_without_folder}/${each.value.bundle}.zip"
  source_dir  = "${local.open_next_path_without_folder}/${each.value.bundle}"
}

data "archive_file" "edge_function" {
  for_each = { for name, edge_function in local.edge_functions : name => edge_function if try(var.edge_functions.function_overrides[name].function_code.zip, null) == null && try(var.edge_functions.function_overrides[name].function_code.s3, null) == null }
  type        = "zip"
  output_path = "${local.open_next_path_without_folder}/${each.value.bundle}.zip"
  source_dir  = "${local.open_next_path_without_folder}/${each.value.bundle}"

  depends_on = [local_file.edge_functions_modifications]
}

data "archive_file" "revalidation_function" {
  count       = try(var.revalidation_function.function_code.zip, null) == null && try(var.revalidation_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${local.open_next_revalidation}.zip"
  source_dir  = local.open_next_revalidation
}

data "archive_file" "image_optimisation_function" {
  count       = try(var.image_optimisation_function.function_code.zip, null) == null && try(var.image_optimisation_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${local.open_next_image_optimisation}.zip"
  source_dir  = local.open_next_image_optimisation
}

data "archive_file" "warmer_function" {
  count       = try(var.warmer_function.function_code.zip, null) == null && try(var.warmer_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${local.open_next_warmer}.zip"
  source_dir  = local.open_next_warmer
}