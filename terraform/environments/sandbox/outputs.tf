output "registry_url" {
  description = "Where the app image lives."
  value       = module.registry.repository_url
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.cluster.name
}

output "region" {
  description = "Region everything was created in."
  value       = var.region
}

output "node_count" {
  description = "How many nodes the cluster should have."
  value       = var.node_count
}

output "allowed_cidr" {
  description = "Who may open the app."
  value       = local.allow_cidr
}

output "app_urls" {
  description = "Addresses of the app, once it is deployed."
  value       = [for ip in module.nodes.public_ips : "http://${ip}:${var.node_port}"]
}
