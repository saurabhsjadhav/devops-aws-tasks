terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # Partial backend configuration. `bucket` and `region` are injected at init time:
  #   terraform init -backend-config="bucket=<state-bucket>" -backend-config="region=<region>"
  # State is encrypted at rest and locked with S3 native lock files (Terraform >= 1.10).
  backend "s3" {
    key          = "devops-task/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
