# providers.tf — No backend block; Harness IACM workspace provides state backend natively.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    harness = {
      source  = "harness/harness"
      version = ">= 0.31"
    }
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      ManagedBy   = "opentofu"
      Environment = var.env
      Workspace   = "ecs-service-group"
    }
  }
}

# Confirmed: harness provider uses HARNESS_PLATFORM_API_KEY and HARNESS_ACCOUNT_ID
# env vars when not set in the block. IACM workspace injects these automatically.
provider "harness" {
  account_id = var.harness_account_id
}
