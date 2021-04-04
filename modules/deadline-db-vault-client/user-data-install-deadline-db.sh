#!/bin/bash

set -e

exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

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

# Store certs with vault

function store_file {
  local -r file_path="$1"
  if [[ -z "$2" ]]; then
    local target="$resourcetier/deadlinedb/client_cert_files/$file_path"
  else
    local target="$2"
  fi

  if sudo test -f "$file_path"; then
    vault kv put -address="$VAULT_ADDR" -format=json $target file="$(sudo cat $file_path)"
    if [[ "$OSTYPE" == "darwin"* ]]; then # Acquire file permissions.
        octal_permissions=$(sudo stat -f %A $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev ) # clip to 4 zeroes
    else
        octal_permissions=$(sudo stat --format '%a' $file_path | rev | sed -E 's/^([[:digit:]]{4})([^[:space:]]+)/\1/' | rev) # clip to 4 zeroes
    fi
    octal_permissions=$( python3 -c "print( \"$octal_permissions\".zfill(4) )" ) # pad to 4 zeroes
    vault kv patch -address="$VAULT_ADDR" -format=json $target permissions="$octal_permissions"
    file_uid="$(sudo stat --format '%u' $file_path)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target owner="$(sudo id -un -- $file_uid)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target uid="$file_uid"
    file_gid="$(sudo stat --format '%g' $file_path)"
    vault kv patch -address="$VAULT_ADDR" -format=json $target gid="$file_gid"
  else
    print "Error: file not found: $file_path"
    exit 1
  fi
}

# Store generated certs in vault

store_file "/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"

set -o history
echo "Done."

# Register the service with consul.  not that it may not be necesary to set the hostname in the beggining of this user data script, especially if we create a cluster in the future.
service_name="deadlinedb"
consul services register -name=$service_name
sleep 5
consul catalog services
dig $service_name.service.consul
result=$(dig +short $service_name.service.consul) && exit_status=0 || exit_status=$?
if [[ ! $exit_status -eq 0 ]]; then echo "No DNS entry found for $service_name.service.consul"; exit 1; fi
