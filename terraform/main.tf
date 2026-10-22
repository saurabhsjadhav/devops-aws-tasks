provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Regional ELB account that is allowed to write ALB access logs (regions launched before Aug 2022).
data "aws_elb_service_account" "main" {}

# Latest Amazon Linux 2023 AMI, resolved from the public SSM parameter.
data "aws_ssm_parameter" "al2023_ami" {
  name            = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  with_decryption = false
}

locals {
  name = "${var.project_name}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # The application is packaged from ../app and delivered to instances through S3.
  # The version is a content hash, so any code change produces a new launch template
  # version and triggers a rolling instance refresh.
  app_dir         = "${path.module}/../app"
  app_files       = sort(fileset(local.app_dir, "*"))
  app_version     = substr(sha256(join("", [for f in local.app_files : filesha256("${local.app_dir}/${f}")])), 0, 12)
  app_package_key = "artifacts/app-${local.app_version}.zip"

  create_certificate = var.certificate_arn == ""
  certificate_arn    = local.create_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.certificate_arn
  create_dns_record  = var.hosted_zone_id != ""
}
