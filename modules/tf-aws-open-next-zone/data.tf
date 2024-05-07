data "aws_region" "current" {}

# Zip Archives

data "archive_file" "server_function" {
  count       = try(var.server_function.function_code.zip, null) == null && try(var.server_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/server-functions.zip"
  source_dir  = "${var.folder_path}/server-functions"

  depends_on = [local_file.lambda_at_edge_modifications]
}

data "archive_file" "revalidation_function" {
  count       = try(var.revalidation_function.function_code.zip, null) == null && try(var.revalidation_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/revalidation-function.zip"
  source_dir  = "${var.folder_path}/revalidation-function"
}

data "archive_file" "image_optimisation_function" {
  count       = try(var.image_optimisation_function.function_code.zip, null) == null && try(var.image_optimisation_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/image-optimization-function.zip"
  source_dir  = "${var.folder_path}/image-optimization-function"
}

data "archive_file" "warmer_function" {
  count       = try(var.warmer_function.function_code.zip, null) == null && try(var.warmer_function.function_code.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/warmer-function.zip"
  source_dir  = "${var.folder_path}/warmer-function"
}
