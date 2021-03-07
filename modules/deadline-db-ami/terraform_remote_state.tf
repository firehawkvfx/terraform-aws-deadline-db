# A module to read the desired instance profile from terraform remote state.
variable "bucket_extension_vault" {
    description = "The bucket extension where the terraform remote state resides"
    type = string
}
variable "resourcetier_vault" {
    description = "The resourcetier the desired vault vpc resides in"
    type = string
}
variable "vpcname_vault" {
    description = "A namespace component defining the location of the terraform remote state"
    type = string
}
data "aws_region" "current" {}
data "terraform_remote_state" "vault_vpc" { # read the arn with data.terraform_remote_state.provisioner_profile.outputs.instance_role_arn, or read the profile name with data.terraform_remote_state.provisioner_profile.outputs.instance_profile_name
  backend = "s3"
  config = {
    bucket = "state.terraform.${var.bucket_extension_vault}"
    key    = "${var.resourcetier_vault}/vaultvpc/terraform.tfstate"
    region = data.aws_region.current.name
  }
}
data "terraform_remote_state" "provisioner_profile" { # read the arn with data.terraform_remote_state.provisioner_profile.outputs.instance_role_arn, or read the profile name with data.terraform_remote_state.provisioner_profile.outputs.instance_profile_name
  backend = "s3"
  config = {
    bucket = "state.terraform.${var.bucket_extension_vault}"
    key    = "${var.resourcetier_vault}/${var.vpcname_vault}-terraform-aws-iam-profile-provisioner/terraform.tfstate"
    region = data.aws_region.current.name
  }
}
output "vpc_id" {
    value = data.terraform_remote_state.vault_vpc.outputs.vpc_id
}
output "public_subnets" {
    value = data.terraform_remote_state.vault_vpc.outputs.public_subnets
}

output "consul_client_security_group" {
    value = data.terraform_remote_state.vault_vpc.outputs.consul_client_security_group
}

output "instance_profile_name" {
    value = data.terraform_remote_state.provisioner_profile.outputs.instance_profile_name
}