data "aws_region" "current" {}

# Zip Archives

data "archive_file" "server_function" {
  count       = try(var.server_function.deployment_artifact.zip, null) == null && try(var.server_function.deployment_artifact.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/server-function.zip"
  source_dir  = "${var.folder_path}/server-function"

  depends_on = [local_file.lambda_at_edge_modifications]
}

data "archive_file" "revalidation_function" {
  count       = try(var.revalidation_function.deployment_artifact.zip, null) == null && try(var.revalidation_function.deployment_artifact.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/revalidation-function.zip"
  source_dir  = "${var.folder_path}/revalidation-function"
}

data "archive_file" "image_optimisation_function" {
  count       = try(var.image_optimisation_function.deployment_artifact.zip, null) == null && try(var.image_optimisation_function.deployment_artifact.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/image-optimization-function.zip"
  source_dir  = "${var.folder_path}/image-optimization-function"
}

data "archive_file" "warmer_function" {
  count       = try(var.warmer_function.deployment_artifact.zip, null) == null && try(var.warmer_function.deployment_artifact.s3, null) == null ? 1 : 0
  type        = "zip"
  output_path = "${var.folder_path}/warmer-function.zip"
  source_dir  = "${var.folder_path}/warmer-function"
}