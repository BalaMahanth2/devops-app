# Credentials come from the shell: export AWS_PROFILE=kk
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "devops-app"
      ManagedBy = "terraform"
    }
  }
}
