terraform {
  source          = "../..//"
  include_in_copy = ["./examples/single-zone/.open-next"]
}

inputs = {
  prefix = "open-next-sz-${get_aws_account_id()}"
  open_next = {
    exclusion_regex  = ".*\\.terragrunt-source-manifest"
    root_folder_path = "./examples/single-zone/.open-next"
  }
}