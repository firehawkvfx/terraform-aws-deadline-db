#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )" # The directory of this script

export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')

# Packer Vars
export PKR_VAR_aws_region="$AWS_DEFAULT_REGION"
if [[ -f "$SCRIPTDIR/../bastion-ami/manifest.json" ]]; then
    export PKR_VAR_bastion_ubuntu18_ami="$(jq -r '.builds[] | select(.name == "ubuntu18-ami") | .artifact_id' $SCRIPTDIR/../bastion-ami/manifest.json | tail -1 | cut -d ":" -f2)"
    echo "Found bastion_ubuntu18_ami in manifest: PKR_VAR_bastion_ubuntu18_ami=$PKR_VAR_bastion_ubuntu18_ami"
fi

if [[ -f "$SCRIPTDIR/../general-host-ami/manifest.json" ]]; then
    export PKR_VAR_general_host_ubuntu18_ami="$(jq -r '.builds[] | select(.name == "general-host-ubuntu18-ami") | .artifact_id' $SCRIPTDIR/../general-host-ami/manifest.json | tail -1 | cut -d ":" -f2)"
    echo "Found general_host_ubuntu18_ami in manifest: PKR_VAR_general_host_ubuntu18_ami=$PKR_VAR_general_host_ubuntu18_ami"
fi

export PACKER_LOG=1
export PACKER_LOG_PATH="$SCRIPTDIR/packerlog.log"

terraform init \
    -input=false
terraform plan -out=tfplan -input=false
terraform apply -input=false tfplan

export PKR_VAR_vpc_id="$(terraform output -json "vpc_id" | jq -r '.')"
echo "Using VPC: $PKR_VAR_vpc_id"
export PKR_VAR_subnet_id="$(terraform output -json "public_subnets" | jq -r '.[0]')"
echo "Using Subnet: $PKR_VAR_subnet_id"
export PKR_VAR_security_group_id="$(terraform output -json "consul_client_security_group" | jq -r '.')"
echo "Using Security Group: $PKR_VAR_security_group_id"
export PKR_VAR_provisioner_iam_profile_name="$(terraform output instance_profile_name)"
echo "Using profile: $PKR_VAR_provisioner_iam_profile_name"

export PKR_VAR_manifest_path="$SCRIPTDIR/manifest.json"

mkdir -p $SCRIPTDIR/tmp/log
rm -f $PKR_VAR_manifest_path
packer build "$@" $SCRIPTDIR/deadline-db.pkr.hcl

