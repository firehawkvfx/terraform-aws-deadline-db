### The details of the backend are provided as vars during terraform init by apply / wake scripts
terraform {
  backend "s3" {
    encrypt        = true
  }
}