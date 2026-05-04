data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket         = "peter-project1-tfstate"
    key            = "vpc/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "peter-project1-tflocks"
  }
}
