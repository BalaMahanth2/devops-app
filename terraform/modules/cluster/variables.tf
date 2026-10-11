variable "name" {
  description = "Name of the cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, for example 1.35."
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role the control plane runs as."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane, in at least two zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}
