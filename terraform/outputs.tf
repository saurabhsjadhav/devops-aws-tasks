output "application_url" {
  description = "Public HTTPS URL of the application."
  value       = "https://${var.domain_name}"
}

output "alb_dns_name" {
  description = "DNS name of the load balancer (create a CNAME to this if DNS is not in Route 53)."
  value       = aws_lb.main.dns_name
}

output "certificate_arn" {
  value = local.certificate_arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.app.name
}

output "rds_endpoint" {
  description = "Private RDS endpoint (reachable only from the app security group)."
  value       = aws_db_instance.main.address
}

output "db_secret_name" {
  description = "Secrets Manager secret that holds the database credentials."
  value       = aws_secretsmanager_secret.db.name
}

output "app_bucket" {
  value = aws_s3_bucket.app.id
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.logs.id
}

output "app_version" {
  description = "Content hash of the deployed application package."
  value       = local.app_version
}
