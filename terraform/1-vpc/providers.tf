terraform {
  required_version = "~> 1.9.0"

  backend "s3" {
    bucket         = "peter-project1-tfstate"
    key            = "vpc/terraform.tfstate"
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
