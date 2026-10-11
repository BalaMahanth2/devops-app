output "name" {
  description = "Name of the cluster."
  value       = aws_eks_cluster.this.name
}

output "endpoint" {
  description = "Address of the Kubernetes API."
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority" {
  description = "Certificate that proves the API is the real one, base64 encoded."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "security_group_id" {
  description = "Firewall that EKS created for the control plane and the nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "service_cidr" {
  description = "Address range Kubernetes uses for Services."
  value       = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
}
