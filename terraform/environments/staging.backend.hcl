# Terraform Backend Configuration for Staging
# S3 state storage with DynamoDB locking

bucket         = "artemis-terraform-state"
key            = "staging/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "artemis-terraform-locks"
