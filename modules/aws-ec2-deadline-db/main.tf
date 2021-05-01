# A vault client host with consul registration and signed host keys from vault.

data "aws_region" "current" {}
resource "aws_security_group" "deadline_db_vault_client" {
  count       = var.create_vpc ? 1 : 0
  name        = var.name
  vpc_id      = var.vpc_id
  description = "Vault client security group"
  tags        = merge(map("Name", var.name), var.common_tags, local.extra_tags)
  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.permitted_cidr_list_private
    description = "all incoming traffic from vpc, vpn dhcp, and remote subnet"
  }
  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    cidr_blocks     = var.permitted_cidr_list
    security_groups = var.security_group_ids
    description     = "SSH"
  }
  ingress {
    protocol        = "tcp"
    from_port       = 8200
    to_port         = 8200
    cidr_blocks     = var.permitted_cidr_list
    security_groups = var.security_group_ids
    description     = "Vault Web UI Forwarding"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 17000
    to_port     = 17003
    cidr_blocks = var.permitted_cidr_list
    # security_groups = var.security_group_ids
    description = "Launcher Listening Port, Deadline Auto Config Port, Deadline Worker / Slave Startup Port"
  }
  # ingress {
  #   protocol    = "tcp"
  #   from_port   = 17001
  #   to_port     = 17001
  #   cidr_blocks = var.permitted_cidr_list
  #   # security_groups = var.security_group_ids
  #   description = "Deadline Auto Config Port"
  # }
  # ingress {
  #   protocol    = "tcp"
  #   from_port   = 17003
  #   to_port     = 17003
  #   cidr_blocks = var.permitted_cidr_list
  #   # security_groups = var.security_group_ids
  #   description = "Deadline Worker / Slave Startup Port"
  # }
  ingress {
    protocol    = "tcp"
    from_port   = 27100
    to_port     = 27100
    cidr_blocks = var.permitted_cidr_list
    # security_groups = var.security_group_ids
    description = "Deadline DB port"
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = var.permitted_cidr_list
    # security_groups = var.security_group_ids
    description = "Deadline HTTP port"
  }
  ingress {
    protocol    = "tcp"
    from_port   = 4433
    to_port     = 4433
    cidr_blocks = var.permitted_cidr_list
    # security_groups = var.security_group_ids
    description = "Deadline TLS port"
  }
  ingress {
    protocol    = "icmp"
    from_port   = 8
    to_port     = 0
    cidr_blocks = var.permitted_cidr_list
    description = "ICMP ping traffic"
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "all outgoing traffic"
  }
}
data "aws_s3_bucket" "software_bucket" {
  bucket = "software.${var.bucket_extension}"
}
resource "aws_s3_bucket_object" "update_scripts" {
  for_each = fileset("${path.module}/scripts/", "*")
  bucket   = data.aws_s3_bucket.software_bucket.id
  key      = each.value
  source   = "${path.module}/scripts/${each.value}"
  etag     = filemd5("${path.module}/scripts/${each.value}")
}
locals {
  resourcetier = var.common_tags["resourcetier"]
  extra_tags = {
    role  = "deadline_db_vault_client"
    route = "private"
  }
  private_ip                                 = element(concat(aws_instance.deadline_db_vault_client.*.private_ip, list("")), 0)
  id                                         = element(concat(aws_instance.deadline_db_vault_client.*.id, list("")), 0)
  deadline_db_vault_client_security_group_id = element(concat(aws_security_group.deadline_db_vault_client.*.id, list("")), 0)
  vpc_security_group_ids                     = [local.deadline_db_vault_client_security_group_id]
  client_cert_file_path                      = "/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"
  client_cert_vault_path                     = "${local.resourcetier}/deadline/client_cert_files${local.client_cert_file_path}"
}
data "template_file" "user_data_auth_client" {
  template = format(
    "%s%s%s%s",
    file("${path.module}/user-data-iam-auth-ssh-host-consul.sh"),
    file("${path.module}/user-data-install-deadline-db.sh"),
    file("${path.module}/user-data-vault-store-file.sh"),
    file("${path.module}/user-data-register-consul-service.sh")
  )
  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    aws_internal_domain      = var.aws_internal_domain
    aws_external_domain      = "" # External domain is not used for internal hosts.
    example_role_name        = "deadline-db-vault-role"

    resourcetier      = local.resourcetier
    db_host_name      = "deadlinedb.service.consul"
    installers_bucket = "software.${var.bucket_extension}"
    deadlineuser_name = "deadlineuser" # Create this user and install software as this user.
    deadline_version  = var.deadline_version
    consul_service    = "deadlinedb"

    client_cert_file_path  = local.client_cert_file_path
    client_cert_vault_path = local.client_cert_vault_path
  }
}
data "terraform_remote_state" "deadline_db_profile" { # read the arn with data.terraform_remote_state.packer_profile.outputs.instance_role_arn, or read the profile name with data.terraform_remote_state.packer_profile.outputs.instance_profile_name
  backend = "s3"
  config = {
    bucket = "state.terraform.${var.bucket_extension_vault}"
    key    = "firehawk-main/modules/terraform-aws-iam-profile-deadline-db/terraform.tfstate"
    region = data.aws_region.current.name
  }
}
data "aws_subnet" "private" {
  for_each = tolist(var.private_subnet_ids)
  id       = each.value
}
locals {
  private_subnet_cidr_blocks = [for s in data.aws_subnet.private : s.cidr_block]
}
resource "aws_instance" "deadline_db_vault_client" {
  depends_on             = [aws_s3_bucket_object.update_scripts]
  count                  = var.create_vpc ? 1 : 0
  private_ip             = cidrhost(local.private_subnet_cidr_blocks[0], var.host_number)
  ami                    = var.deadline_db_ami_id
  instance_type          = var.instance_type
  key_name               = var.aws_key_name # The PEM key is disabled for use in production, can be used for debugging.  Instead, signed SSH certificates should be used to access the host.
  subnet_id              = tolist(var.private_subnet_ids)[0]
  tags                   = merge(map("Name", var.name), var.common_tags, local.extra_tags)
  user_data              = data.template_file.user_data_auth_client.rendered
  iam_instance_profile   = data.terraform_remote_state.deadline_db_profile.outputs.instance_profile_name
  vpc_security_group_ids = local.vpc_security_group_ids
  root_block_device {
    delete_on_termination = true
  }
}
