terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72"
    }
  }
}

variable "region" {
  description = "AWS region for the provider."
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region = var.region
}

module "backup" {
  source = "../.."

  vault_name = "example-vault"
  plan_name  = "example-plan"

  rules = [
    {
      rule_name    = "daily"
      schedule     = "cron(0 5 * * ? *)"
      delete_after = 30
    }
  ]

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "backup_plan_arn" {
  value = module.backup.plan_arn
}
