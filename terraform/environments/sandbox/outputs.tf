output "registry_url" {
  description = "Where the app image lives."
  value       = module.registry.repository_url
}
