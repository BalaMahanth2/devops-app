variable "region" {
  description = "AWS region. The sandbox only allows a few US regions."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the image repository."
  type        = string
  default     = "devops-app"
}
