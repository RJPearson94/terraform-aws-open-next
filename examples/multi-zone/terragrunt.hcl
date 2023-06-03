terraform {
  source          = "../..//"
  include_in_copy = ["./examples/multi-zone/docs/.open-next", "./examples/multi-zone/home/.open-next"]
}

inputs = {
  prefix = "open-next-multi-zone-testing"
  open_next = {
    exclusion_regex  = ".*\\.terragrunt-source-manifest"
    root_folder_path = "./examples/multi-zone/home/.open-next"
    additional_zones = [{
      name = "docs"
      http_path = "docs"
      folder_path = "./examples/multi-zone/docs/.open-next"
    }]
  }
}