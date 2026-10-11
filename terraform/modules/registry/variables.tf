variable "name" {
  description = "Name of the image repository."
  type        = string
}

variable "force_delete" {
  description = "Delete the repository even when it still holds images."
  type        = bool
  default     = false
}
