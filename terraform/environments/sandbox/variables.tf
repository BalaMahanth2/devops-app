variable "region" {
  description = "AWS region. The sandbox only allows a few US regions."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the image repository and of the cluster."
  type        = string
  default     = "devops-app"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version."
  type        = string
  default     = "1.35"
}

variable "node_count" {
  description = "How many nodes to run."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 4
    error_message = "Use between 1 and 4 nodes; the sandbox is small."
  }
}

variable "node_port" {
  description = "Port on every node that leads to the app."
  type        = number
  default     = 30080
}

variable "allow_cidr" {
  description = "Address range that may open the app. Leave empty to allow only this laptop's network."
  type        = string
  default     = null

  validation {
    condition     = var.allow_cidr == null || can(cidrhost(var.allow_cidr, 0))
    error_message = "Use CIDR form, for example 203.0.113.7/32 or 0.0.0.0/0."
  }
}
