terraform {
  backend "s3" {
    bucket         = "pboyd-io-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pboyd-io-terraform-locks"
    encrypt        = true
  }
}

#dynamodb_table_name = "pboyd-io-terraform-locks"
#state_bucket_name = "pboyd-io-terraform-state"
