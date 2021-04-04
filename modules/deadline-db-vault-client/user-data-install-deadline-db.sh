#!/bin/bash

if $(has_yum); then
    hostname=$(hostname -s) # in centos, failed dns lookup can cause commands to slowdown
    echo "127.0.0.1   $hostname.${aws_internal_domain} $hostname" | tee -a /etc/hosts
    hostnamectl set-hostname $hostname.${aws_internal_domain} # Red hat recommends that the hostname uses the FQDN.  hostname -f to resolve the domain may not work at this point on boot, so we use a var.
    # systemctl restart network # we restart the network later, needed to update the host name
fi

log "hostname: $(hostname)"
log "hostname: $(hostname -f) $(hostname -s)"

# Install Deadline DB and RCS with certificates
sudo -u ubuntu git clone --branch ${deadline_installer_script_branch} ${deadline_installer_script_repo} /home/ubuntu/packer-firehawk-amis
sudo -u ubuntu /home/ubuntu/packer-firehawk-amis/modules/firehawk-ami/scripts/deadlinedb_install_with_certs.sh

# Register the service with consul.  not that it may not be necesary to set the hostname in the beggining of this user data script, especially if we create a cluster in the future.
service_name="deadlinedb"
consul services register -name=$service_name
sleep 5
consul catalog services
dig $service_name.service.consul
result=$(dig +short $service_name.service.consul) && exit_status=0 || exit_status=$?
if [[ ! $exit_status -eq 0 ]]; then echo "No DNS entry found for $service_name.service.consul"; exit 1; fi
