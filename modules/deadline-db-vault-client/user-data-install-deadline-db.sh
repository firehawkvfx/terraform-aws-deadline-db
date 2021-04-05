#!/bin/bash

set -e
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# User Defaults: these will be replaced with terraform template vars, defaults are provided to allow copy / paste directly into a shell for debugging.  These values will not be used when deployed.
deadlineuser_name="deadlineuser"
resourcetier="dev"
installers_bucket="software.$resourcetier.firehawkvfx.com"
deadline_version="10.1.9.2"

# User Vars: Set by terraform template
deadlineuser_name="${deadlineuser_name}"
resourcetier="${resourcetier}"
installers_bucket="${installers_bucket}"
deadline_version="${deadline_version}"

# Script vars (implicit)
VAULT_ADDR=https://vault.service.consul:8200
client_cert_file_path="/opt/Thinkbox/certs/Deadline10RemoteClient.pfx"
client_cert_vault_path="$resourcetier/deadline/client_cert_files/$client_cert_file_path"
installer_file="install-deadlinedb-with-certs.sh"
installer_path="/home/$deadlineuser_name/Downloads/$installer_file"

# Functions
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
    echo "$description"
    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    errors=$(echo "$output") | grep '^{' | jq -r .errors
    echo "$output"
    if [[ $exit_status -eq 0 && -z "$errors" ]]; then
      echo "$output"
      return
    fi
    echo "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;
  echo "$description failed after $attempts attempts."
  exit $exit_status
}
function store_file {
  local -r file_path="$1"
  if [[ -z "$2" ]]; then
    local target="$resourcetier/files/$file_path"
  else
    local target="$2"
  fi
  if sudo test -f "$file_path"; then
    vault kv put -address="$VAULT_ADDR" -format=json $target file="$(sudo cat $file_path | base64 -w 0)"
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
    vault kv patch -address="$VAULT_ADDR" -format=json $target format="base64"
  else
    print "Error: file not found: $file_path"
    exit 1
  fi
}

### Centos 7 fix: Failed dns lookup can cause sudo commands to slowdown
if $(has_yum); then
    hostname=$(hostname -s) 
    echo "127.0.0.1   $hostname.${aws_internal_domain} $hostname" | tee -a /etc/hosts
    hostnamectl set-hostname $hostname.${aws_internal_domain} # Red hat recommends that the hostname uses the FQDN.  hostname -f to resolve the domain may not work at this point on boot, so we use a var.
    # systemctl restart network # we restart the network later, needed to update the host name
fi

### Create deadlineuser
function add_sudo_user() {
  local -r user_name="$1"
  if $(has_apt_get); then
    sudo_group=sudo
  elif $(has_yum); then
    sudo_group=wheel
  else
    echo "ERROR: Could not find apt-get or yum."
    exit 1
  fi
  echo "Adding user: $user_name with groups: $sudo_group $user_name"
  sudo useradd -m -d /home/$user_name/ -s /bin/bash -G $sudo_group $user_name
  echo "Adding user as passwordless sudoer."
  touch "/etc/sudoers.d/98_$user_name"; grep -qxF "$user_name ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/98_$user_name || echo "$user_name ALL=(ALL) NOPASSWD:ALL" >> "/etc/sudoers.d/98_$user_name"
  sudo -i -u $user_name mkdir -p /home/$user_name/.ssh
  # Generate a public and private key - some tools can fail without one.
  sudo -i -u $user_name bash -c "ssh-keygen -q -b 2048 -t rsa -f /home/$user_name/.ssh/id_rsa -C \"\" -N \"\""  
}
add_sudo_user $deadlineuser_name

### Vault Auth IAM Method CLI
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
echo "Erasing old certificate before install process."
vault kv delete -address="$VAULT_ADDR" "$client_cert_vault_path"
echo "Revoking vault token..."
vault token revoke -self

### Install Deadline
# DB and RCS with certificates
mkdir -p "$(dirname $installer_path)"
aws s3api get-object --bucket "$installers_bucket" --key "$installer_file" "$installer_path"
chown $deadlineuser_name:$deadlineuser_name $installer_path
chmod u+x $installer_path
sudo -i -u $deadlineuser_name installers_bucket="$installers_bucket" deadlineuser_name="$deadlineuser_name" deadline_version="$deadline_version" $installer_path

### Vault Auth IAM Method CLI
retry \
  "vault login --no-print -method=aws header_value=vault.service.consul role=${example_role_name}" \
  "Waiting for Vault login"
# Store generated certs in vault
store_file "$client_cert_file_path" "$client_cert_vault_path"
echo "Revoking vault token..."
vault token revoke -self

# Register the service with consul.  not that it may not be necesary to set the hostname in the beggining of this user data script, especially if we create a cluster in the future.
echo "...Registering service with consul"
service_name="deadlinedb"
consul services register -name=$service_name
sleep 5
consul catalog services
dig $service_name.service.consul
result=$(dig +short $service_name.service.consul) && exit_status=0 || exit_status=$?
if [[ ! $exit_status -eq 0 ]]; then echo "No DNS entry found for $service_name.service.consul"; exit 1; fi
