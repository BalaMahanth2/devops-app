output "public_ips" {
  description = "Public address of every node."
  value       = aws_instance.this[*].public_ip
}
