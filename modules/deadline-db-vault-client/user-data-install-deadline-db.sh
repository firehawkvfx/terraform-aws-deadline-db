#!/bin/bash

set -e
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# User Defaults: these will be replaced with terraform template vars, defaults are provided to allow copy / paste directly into a shell for debugging.  These values will not be used when deployed.
deadlineuser_name="deadlineuser"
resourcetier="dev"
installers_bucket="software.$resourcetier.firehawkvfx.com"
example_role_name="deadline-db-vault-role"

# User Vars: Set by terraform template
deadlineuser_name="${deadlineuser_name}"
resourcetier="${resourcetier}"
installers_bucket="${installers_bucket}"
deadline_version="${deadline_version}"
example_role_name="${example_role_name}"

# Script vars (implicit)
export VAULT_ADDR="https://vault.service.consul:8200"
client_cert_vault_path="${client_cert_vault_path}" # the path will be erased before installation commences
# installer_file="install-deadlinedb"
installer_path="/var/tmp/install-deadlinedb"

# Functions
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}
function has_yum {
  [[ -n "$(command -v yum)" ]]
}
function has_apt_get {
  [[ -n "$(command -v apt-get)" ]]
}
# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"
  attempts=5

  for i in $(seq 1 $attempts); do
    log "$description"

    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    errors=$(echo "$output") | grep '^{' | jq -r .errors

    log "$output"

    if [[ $exit_status -eq 0 && -z "$errors" ]]; then
      echo "$output"
      return
    fi
    log "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;

  log "$description failed after $attempts attempts."
  exit $exit_status
}

### Centos 7 fix: Failed dns lookup can cause sudo commands to slowdown
if $(has_yum); then
    hostname="${db_host_name}"
    echo "127.0.0.1   $hostname.${aws_internal_domain} $hostname" | tee -a /etc/hosts
    hostnamectl set-hostname $hostname.${aws_internal_domain} # Red hat recommends that the hostname uses the FQDN.  hostname -f to resolve the domain may not work at this point on boot, so we use a var.
    # systemctl restart network # we restart the network later, needed to update the host name
fi

# ### Create deadlineuser
# function add_sudo_user() {
#   local -r user_name="$1"
#   if $(has_apt_get); then
#     sudo_group=sudo
#   elif $(has_yum); then
#     sudo_group=wheel
#   else
#     echo "ERROR: Could not find apt-get or yum."
#     exit 1
#   fi
#   echo "Adding user: $user_name with groups: $sudo_group $user_name"
#   sudo useradd -m -d /home/$user_name/ -s /bin/bash -G $sudo_group $user_name
#   echo "Adding user as passwordless sudoer."
#   touch "/etc/sudoers.d/98_$user_name"; grep -qxF "$user_name ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/98_$user_name || echo "$user_name ALL=(ALL) NOPASSWD:ALL" >> "/etc/sudoers.d/98_$user_name"
#   sudo -i -u $user_name mkdir -p /home/$user_name/.ssh
#   # Generate a public and private key - some tools can fail without one.
#   sudo -i -u $user_name bash -c "ssh-keygen -q -b 2048 -t rsa -f /home/$user_name/.ssh/id_rsa -C \"\" -N \"\""  
# }
# add_sudo_user $deadlineuser_name

### Vault Auth IAM Method CLI
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
echo "Erasing old certificate before install process."

function erase_vault_file() {
  local -r client_cert_vault_path="$client_cert_vault_path"
  vault kv delete -address="$VAULT_ADDR" "$client_cert_vault_path/file"
  vault kv delete -address="$VAULT_ADDR" "$client_cert_vault_path/permissions"
}
erase_vault_file $client_cert_vault_path

echo "Revoking vault token..."
vault token revoke -self

### Install Deadline # Generate certs after install test
sudo -i -u $deadlineuser_name $installer_path --deadline-version "$deadline_version" --db-host-name "${db_host_name}" --skip-download-installers --skip-install-db --post-certgen-db --skip-install-rcs --post-certgen-rcs

