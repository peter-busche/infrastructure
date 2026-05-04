terraform {
  required_version = "~> 1.9.0"

  # STEP 1: First apply with local backend (leave this commented out).
  # STEP 2: After `terraform apply` succeeds, uncomment the block below
  #         and run `terraform init -migrate-state` to move state to S3.
  #
  backend "s3" {
    bucket         = "peter-project1-tfstate"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "peter-project1-tflocks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}
