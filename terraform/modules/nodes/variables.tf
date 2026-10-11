variable "cluster_name" {
  description = "Name of the cluster the nodes join."
  type        = string
}

variable "cluster_endpoint" {
  description = "Address of the Kubernetes API."
  type        = string
}

variable "cluster_certificate_authority" {
  description = "Certificate of the Kubernetes API, base64 encoded."
  type        = string
}

variable "cluster_service_cidr" {
  description = "Address range Kubernetes uses for Services."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Firewall shared by the control plane and the nodes."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version; picks the matching machine image."
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role and instance profile for the nodes."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets to place the nodes in, one after another."
  type        = list(string)
}

variable "node_count" {
  description = "How many nodes to run."
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 machine size for each node."
  type        = string
  default     = "t3.medium"
}

variable "node_port" {
  description = "Port on every node that leads to the app."
  type        = number
  default     = 30080
}

variable "allow_cidr" {
  description = "Address range that may open the app."
  type        = string
}
