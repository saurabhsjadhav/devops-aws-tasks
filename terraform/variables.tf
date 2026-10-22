############################
# General
############################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names."
  type        = string
  default     = "devops-task"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 characters: lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

############################
# Networking
############################
variable "vpc_cidr" {
  description = "CIDR block of the VPC. /24 subnets are carved out of it automatically."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets and instances across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for a highly available layout."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheaper, single point of failure). false = one NAT gateway per AZ (highly available)."
  type        = bool
  default     = false
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the load balancer on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

############################
# HTTPS / DNS
############################
variable "domain_name" {
  description = "Fully qualified domain name served by the ALB, e.g. app.example.com."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID that contains domain_name. Used for ACM DNS validation and the alias record. Leave empty if DNS is hosted elsewhere."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of an existing, issued ACM certificate for domain_name. Leave empty to have Terraform request and DNS-validate one (requires hosted_zone_id)."
  type        = string
  default     = ""
}

############################
# Compute
############################
variable "instance_type" {
  description = "EC2 instance type for the application servers."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

############################
# Database
############################
variable "db_engine_version" {
  description = "MySQL major version."
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  description = "Upper limit for RDS storage autoscaling."
  type        = number
  default     = 50
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_multi_az" {
  description = "Deploy a synchronous standby in a second AZ."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  description = "Set to true for anything beyond a demo."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Set to false for anything beyond a demo."
  type        = bool
  default     = true
}

############################
# Storage / safety switches
############################
variable "force_destroy_buckets" {
  description = "Allow terraform destroy to delete non-empty S3 buckets. Keep true for the demo, false in production."
  type        = bool
  default     = true
}

variable "alb_log_retention_days" {
  description = "Days to keep ALB access logs."
  type        = number
  default     = 90
}

variable "alb_deletion_protection" {
  type    = bool
  default = false
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window. 0 deletes immediately (so the stack can be re-created with the same name); use 7-30 in production."
  type        = number
  default     = 0
}
