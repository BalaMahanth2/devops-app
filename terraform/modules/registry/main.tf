terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_ecr_repository" "this" {
  name = var.name

  # A tag can never be moved to different content.
  image_tag_mutability = "IMMUTABLE"

  # Lets "terraform destroy" remove the repository while it still holds images.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
}
