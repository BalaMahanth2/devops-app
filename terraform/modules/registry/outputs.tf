output "repository_url" {
  description = "Address to push to and pull from, without a tag."
  value       = aws_ecr_repository.this.repository_url
}
