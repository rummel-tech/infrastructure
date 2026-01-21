# Provider Configuration
# Note: Main terraform and provider blocks are in main.tf
# This file contains additional provider configurations if needed

# Provider for us-east-1 (required for CloudFront certificates)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
