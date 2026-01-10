# This file should be configured after running the bootstrap
# Run: cd bootstrap && terraform init && terraform apply
# Then copy the backend configuration from the outputs here
#
# terraform {
#   backend "s3" {
#     bucket         = "pboyd-io-terraform-state"
#     key            = "terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "pboyd-io-terraform-locks"
#     encrypt        = true
#   }
# }
