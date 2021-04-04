#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in client mode, and vault to sign the host key. Note that this script assumes it's running in an AMI
# built from the Packer template in firehawk-main/modules/terraform-aws-vault-client/modules/vault-client-ami

set -e

# Send the log output from this script to user-data.log, syslog, and the console. From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee -a /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Log the given message. All logs are written to stderr with a timestamp.
function log {
 local -r message="$1"
 local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
 >&2 echo -e "$timestamp $message"
}

log "Signing SSH host key done. Revoking vault token..."
vault token revoke -self

# if this script fails, we can set the instance health status but we need to capture a fault
# aws autoscaling set-instance-health --instance-id i-0b03e12682e74746e --health-status Unhealthy
