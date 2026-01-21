# Terraform Backend Configuration for Production
# S3 state storage with DynamoDB locking

bucket         = "artemis-terraform-state"
key            = "production/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "artemis-terraform-locks"
