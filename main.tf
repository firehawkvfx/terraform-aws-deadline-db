provider "null" {
  version = "~> 3.0"
}

provider "aws" {
  #  if you haven't installed and configured the aws cli, you will need to provide your aws access key and secret key.
  # in a dev environment these version locks below can be disabled.  in production, they should be locked based on the suggested versions from terraform init.
  version = "~> 3.15.0"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_canonical_user_id" "current" {}

locals {
  common_tags = var.common_tags
}

data "aws_vpc" "primary" {
  default = false
  tags    = local.common_tags
}
data "aws_internet_gateway" "gw" {
  # default = false
  tags = local.common_tags
}

data "aws_subnet_ids" "public" {
  vpc_id = data.aws_vpc.primary.id
  tags   = map("area", "public")
}

data "aws_subnet" "public" {
  for_each = data.aws_subnet_ids.public.ids
  id       = each.value
}

data "aws_subnet_ids" "private" {
  vpc_id = data.aws_vpc.primary.id
  tags   = map("area", "private")
}

data "aws_subnet" "private" {
  for_each = data.aws_subnet_ids.private.ids
  id       = each.value
}

data "aws_route_tables" "public" {
  vpc_id = data.aws_vpc.primary.id
  tags   = map("area", "public")
}

data "aws_route_tables" "private" {
  vpc_id = data.aws_vpc.primary.id
  tags   = map("area", "private")
}

data "vault_generic_secret" "private_domain" { # Get the map of data at the path
  path = "${local.mount_path}/network/private_domain"
}

# data "vault_generic_secret" "onsite_public_ip" { # The remote onsite IP address
#   path = "${local.mount_path}/network/onsite_public_ip"
# }

# data "vault_generic_secret" "vpn_cidr" { # Get the map of data at the path
#   path = "${local.mount_path}/network/vpn_cidr"
# }
# data "vault_generic_secret" "onsite_private_subnet_cidr" { # Get the map of data at the path
#   path = "${local.mount_path}/network/onsite_private_subnet_cidr"
# }
data "aws_security_group" "bastion" { # Aquire the security group ID for external bastion hosts, these will require SSH access to this internal host.  Since multiple deployments may exist, the pipelineid allows us to distinguish between unique deployments.
  tags   = map("Name", "bastion_pipeid${lookup(local.common_tags, "pipelineid", "0")}")
  vpc_id = data.aws_vpc.primary.id
}

locals {
  mount_path           = var.resourcetier
  vpc_id               = data.aws_vpc.primary.id
  vpc_cidr             = data.aws_vpc.primary.cidr_block
  aws_internet_gateway = data.aws_internet_gateway.gw.id

  vpn_cidr                   = var.vpn_cidr
  onsite_private_subnet_cidr = var.onsite_private_subnet_cidr

  private_subnet_ids         = tolist(data.aws_subnet_ids.private.ids)
  private_subnet_cidr_blocks = [for s in data.aws_subnet.private : s.cidr_block]
  private_domain             = lookup(data.vault_generic_secret.private_domain.data, "value")
  onsite_public_ip           = var.onsite_public_ip
  private_route_table_ids    = data.aws_route_tables.private.ids
  # public_route_table_ids     = data.aws_route_tables.public.ids
  # public_domain_name         = "none"
}
module "deadline_db_vault_client" {
  source             = "./modules/deadline-db-vault-client"
  name               = "deadlinedbvaultclient_pipeid${lookup(local.common_tags, "pipelineid", "0")}"
  deadline_db_ami_id = var.deadline_db_ami_id

  consul_cluster_name    = var.consul_cluster_name
  consul_cluster_tag_key = var.consul_cluster_tag_key
  aws_internal_domain    = var.aws_internal_domain
  vpc_id                 = local.vpc_id
  vpc_cidr               = local.vpc_cidr

  bucket_extension_vault = var.bucket_extension_vault
  private_subnet_ids     = local.private_subnet_ids
  permitted_cidr_list    = ["${local.onsite_public_ip}/32", var.remote_cloud_public_ip_cidr, var.remote_cloud_private_ip_cidr, local.onsite_private_subnet_cidr, local.vpn_cidr]
  security_group_ids     = [data.aws_security_group.bastion.id]

  aws_key_name = var.aws_key_name
  common_tags  = local.common_tags
}
