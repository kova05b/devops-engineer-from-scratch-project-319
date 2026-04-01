locals {
  name_prefix = var.project_name

  labels = {
    project = var.project_name
    env     = "dev"
  }
}

