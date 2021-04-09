#!/bin/bash

# This installs certificates with the DB.

set -e

# User vars
installers_bucket="${installers_bucket}"
deadlineuser_name="${deadlineuser_name}"
deadline_version="${deadline_version}"
download_dir="/var/tmp/downloads"
dbport="27100"
db_host_name="deadlinedb.service.consul"
deadline_proxy_certificate="Deadline10RemoteClient.pfx"
deadline_client_certificate="Deadline10Client.pfx"
mongo_url="https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1604-3.6.19.tgz"

# Script vars (implicit)
deadline_proxy_root_dir="$db_host_name:4433"
deadline_client_certificate_basename="${deadline_client_certificate%.*}"
deadline_linux_installers_tar="/tmp/Deadline-${deadline_version}-linux-installers.tar"
deadline_linux_installers_filename="$(basename $deadline_linux_installers_tar)"
deadline_linux_installers_basename="${deadline_linux_installers_filename%.*}"
deadline_installer_dir="$download_dir/$deadline_linux_installers_basename"
server_cert_basename="$db_host_name"
deadline_proxy_certificate_basename="${deadline_proxy_certificate%.*}"
mongo_installer_tgz="$download_dir/$(basename $mongo_url)"
deadline_db_installer_filename="DeadlineRepository-${deadline_version}-linux-x64-installer.run"
deadline_client_installer_filename="DeadlineClient-${deadline_version}-linux-x64-installer.run"

# set hostname
cat /etc/hosts | grep -m 1 "127.0.0.1   $db_host_name" || echo "127.0.0.1   $db_host_name" | sudo tee -a /etc/hosts
sudo hostnamectl set-hostname $db_host_name

# Functions
function replace_line() {
  local -r filepath=$1
  local -r start=$2
  local -r end=$3
  PYTHON_CODE=$(cat <<END
import argparse
import sys
import fileinput
print("open: {} replace after: {} with: {}".format( "$filepath", "$start", "$end" ))
for line in fileinput.input(["$filepath"], inplace=True):
    if line.startswith("$start"):
        line = '{}\n'.format( "$end" )
    sys.stdout.write(line)
END
)
  sudo python3 -c "$PYTHON_CODE"
}
function ensure_value() { # If the pattern matches, the value will be replaced, otherwise it willl be appended.
  local -r filepath=$1
  local -r start=$2
  local -r end=$3
  PYTHON_CODE=$(cat <<END
import argparse
import sys
import fileinput
print("open: {} replace after: {} with: {}".format( "$filepath", "$start", "$end" ))
replaced=False
for line in fileinput.input(["$filepath"], inplace=True):
    if line.startswith("$start"):
        line = '{}{}\n'.format( "$start", "$end" )
        replaced=True
    sys.stdout.write(line)
if replaced==False: # Append if no match
    with open("$filepath", "a") as file_object:
        line = '{}{}\n'.format( "$start", "$end" )
        file_object.write(line)
END
)
  sudo python3 -c "$PYTHON_CODE"
}

# ensure directory exists
# sudo mkdir -p "/home/$deadlineuser_name/Downloads"
# sudo chown $deadlineuser_name:$deadlineuser_name "/home/$deadlineuser_name/Downloads"

# # Download mongo
# if [[ -f "$mongo_installer_tgz" ]]; then
#     echo "File already exists: $mongo_installer_tgz"
# else
#     wget $mongo_url -O $mongo_installer_tgz
# fi
# # Download Deadline
# if [[ -f "$deadline_linux_installers_tar" ]]; then
#     echo "File already exists: $deadline_linux_installers_tar"
# else
#     # Prefer installation from Thinkbox S3 Bucket for visibility when a version is deprecated.
#     output=$(aws s3api head-object --bucket thinkbox-installers --key "Deadline/${deadline_version}/Linux/${deadline_linux_installers_filename}") && exit_status=0 || exit_status=$?
#     if [[ $exit_status -eq 0 ]]; then
#         echo "...Downloading Deadline from: thinkbox-installers"
#         aws s3api get-object --bucket thinkbox-installers --key "Deadline/${deadline_version}/Linux/${deadline_linux_installers_filename}" "${deadline_linux_installers_tar}"
#         # If this doesn't exist in user bucket, upload it for reproducibility (incase the Thinkbox installer becomes unavailable).
#         echo "...Querying if this file exists in $installers_bucket"
#         output=$(aws s3api head-object --bucket $installers_bucket --key "$deadline_linux_installers_filename") && exit_status=0 || exit_status=$?
#         if [[ ! $exit_status -eq 0 ]]; then
#             echo "Uploading the file to $installers_bucket $deadline_linux_installers_filename"
#             aws s3api put-object --bucket $installers_bucket --key "$deadline_linux_installers_filename" --body "${deadline_linux_installers_tar}"
#         else
#             echo "The bucket $installers_bucket already contains: $deadline_linux_installers_filename"
#         fi
#     else
#         printf "\n\nWarning: The installer was not aquired from Thinkbox.  It may have become deprecated.  Other AWS Accounts will not be able to install this version.\n\n"
#         echo "...Downloading from: $installers_bucket"
#         aws s3api get-object --bucket $installers_bucket --key "$deadline_linux_installers_filename" "${deadline_linux_installers_tar}"
#     fi
# fi
echo "Setup directories and permissions."
# Directories and permissions
sudo mkdir -p /opt/Thinkbox
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox
sudo chmod u=rwX,g=rX,o-rwx /opt/Thinkbox

# DB certs by default live here
deadline_certificates_location="/opt/Thinkbox/DeadlineDatabase10/certs"
sudo mkdir -p "$deadline_certificates_location"
sudo chown $deadlineuser_name:$deadlineuser_name $deadline_certificates_location
sudo chmod u=rwX,g=rX,o-rwx "$deadline_certificates_location"

# Client certs live here
deadline_client_certificates_location="/opt/Thinkbox/certs"
sudo mkdir -p "$deadline_client_certificates_location"
sudo chown $deadlineuser_name:$deadlineuser_name $deadline_client_certificates_location
sudo chmod u=rwX,g=rX,o-rwx "$deadline_client_certificates_location"

sudo mkdir -p $deadline_installer_dir

echo "...Installing Deadline DB."
# Extract Installer
# sudo tar -xvf $deadline_linux_installers_tar -C $deadline_installer_dir
# Install Deadline DB
sudo $deadline_installer_dir/$deadline_db_installer_filename \
--mode unattended \
--debuglevel 2 \
--prefix /opt/Thinkbox/DeadlineRepository10 \
--setpermissions true \
--installmongodb true \
--prepackagedDB $mongo_installer_tgz \
--dbOverwrite true \
--mongodir /opt/Thinkbox/DeadlineDatabase10 \
--dbListeningPort $dbport \
--dbhost $db_host_name \
--dbport $dbport \
--dbuser $deadlineuser_name \
--dbauth true \
--certgen_outdir $deadline_certificates_location \
--createX509dbuser true \
--requireSSL true \
--dbssl true
# --dbpassword avaultpassword \
# --certgen_password avaultpassword \
# --dbcertpass avaultpassword


# stop service before updating config.
sudo service Deadline10db stop


# After DB install, certs exist here
# ls -ltriah /opt/Thinkbox/DeadlineDatabase10/certs/
# total 24K
# 522562 drwxr-xr-x 4 root   root   4.0K Apr  3 23:27 ..
# 768030 -r--r----- 1 ubuntu ubuntu 1.2K Apr  3 23:27 ca.crt
# 768038 -r--r----- 1 ubuntu ubuntu 3.3K Apr  3 23:27 Deadline10Client.pfx
# 768034 -r--r----- 1 ubuntu ubuntu 2.9K Apr  3 23:27 deadlinedb.service.consul.pem
# 768036 -r--r----- 1 ubuntu ubuntu 3.0K Apr  3 23:27 mongo_client.pem

# and after RCS:
# ls -ltriah /opt/Thinkbox/certs/
# total 20K
# 521283 -r-------- 1 ubuntu root   1.2K Apr  3 23:29 ca.crt
# 521289 -r-------- 1 ubuntu root   3.3K Apr  3 23:29 deadlinedb.service.consul.pfx
# 521292 -r-------- 1 root   root   3.3K Apr  3 23:29 Deadline10RemoteClient.pfx

#MongoDB config file
# systemLog:
#   destination: file
#   # Mongo DB's output will be logged here.
#   path: /opt/Thinkbox/DeadlineDatabase10/mongo/data/logs/log.txt
#   # Default to quiet mode to limit log output size. Set to 'false' when debugging.
#   quiet: true
#   # Increase verbosity level for more debug messages (max: 5)
#   verbosity: 0
# net:
#   # Port MongoDB will listen on for incoming connections
#   port: 27100
#   ipv6: true
#   ssl:
#     # SSL/TLS options
#     mode: requireSSL
#     # If enabling TLS, the below options need to be set:
#     PEMKeyFile: /opt/Thinkbox/DeadlineDatabase10/certs/deadlinedb.service.consul.pem
#     CAFile: /opt/Thinkbox/DeadlineDatabase10/certs/ca.crt
#   # By default mongo will only use localhost, this will allow us to use the IP Address
#   bindIpAll: true
# storage:
#   # Database files will be stored here
#   dbPath: /opt/Thinkbox/DeadlineDatabase10/mongo/data
#   engine: wiredTiger
# security:
#   authorization: enabled

sudo chown ubuntu:ubuntu $deadline_certificates_location/*

# finalize permissions post install:
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/
sudo chmod u+rX,g+rX,o-rwx /opt/Thinkbox/

sudo chown $deadlineuser_name:$deadlineuser_name $deadline_certificates_location
sudo chmod u+rX,g+rX,o-rwx $deadline_certificates_location

sudo chown $deadlineuser_name:$deadlineuser_name $deadline_client_certificates_location
sudo chmod u+rX,g+rX,o-rwx $deadline_client_certificates_location

sudo chown -R $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/DeadlineRepository10
sudo chmod -R u=rX,g=rX,o-rwx /opt/Thinkbox/DeadlineRepository10

sudo chown -R $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/DeadlineRepository10/jobs
sudo chmod -R u=rwX,g=rwX,o-rwx /opt/Thinkbox/DeadlineRepository10/jobs

sudo chown -R $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/DeadlineRepository10/jobsArchived
sudo chmod -R u=rwX,g=rwX,o-rwx /opt/Thinkbox/DeadlineRepository10/jobsArchived

sudo chown -R $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/DeadlineRepository10/reports
sudo chmod -R u=rwX,g=rwX,o-rwx /opt/Thinkbox/DeadlineRepository10/reports

# Restart Deadline / Mongo service
sudo systemctl daemon-reload
sudo service Deadline10db start

# Directories and Permissions
sudo apt-get install -y xdg-utils
sudo apt-get install -y lsb # required for render nodes as well
sudo mkdir -p /usr/share/desktop-directories
sudo mkdir -p /opt/Thinkbox/DeadlineRepository10
sudo chmod u=rwX,g=rwX,o=r /opt/Thinkbox/DeadlineRepository10

echo "...Installing Deadline Client: RCS."

# Install Client:
# Deadline RCS
sudo $deadline_installer_dir/$deadline_client_installer_filename \
--mode unattended \
--launcherdaemon true \
--enable-components proxyconfig \
--servercert "${deadline_certificates_location}/${deadline_client_certificate}" \
--debuglevel 2 \
--prefix /opt/Thinkbox/Deadline10 \
--connectiontype Repository \
--repositorydir /opt/Thinkbox/DeadlineRepository10/ \
--dbsslcertificate "${deadline_certificates_location}/${deadline_client_certificate}" \
--licensemode UsageBased \
--daemonuser "$deadlineuser_name" \
--connserveruser "$deadlineuser_name" \
--httpport 8080 \
--tlsport 4433 \
--enabletls true \
--tlscertificates generate  \
--generatedcertdir "${deadline_client_certificates_location}/" \
--slavestartup false \
--proxyrootdir $deadline_proxy_root_dir \
--proxycertificate $deadline_client_certificates_location/$deadline_proxy_certificate
# --dbsslpassword avaultpassword \
# --clientcert_pass avaultpassword \
# --proxycertificatepassword avaultpassword

# Configure /var/lib/Thinkbox/Deadline10/deadline.ini
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "LaunchPulseAtStartup=" "True"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "LaunchRemoteConnectionServerAtStartup=" "True"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "ProxyRoot=" "$deadline_proxy_root_dir"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "ProxyUseSSL=" "True"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "DbSSLCertificate=" "$deadline_certificates_location/$deadline_client_certificate"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "ProxySSLCertificate=" "$deadline_client_certificates_location/$deadline_proxy_certificate"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "ProxyRoot0=" "$deadline_proxy_root_dir;$deadline_client_certificates_location/$deadline_proxy_certificate"
ensure_value "/var/lib/Thinkbox/Deadline10/deadline.ini" "NetworkRoot0=" "/opt/Thinkbox/DeadlineRepository10/;$deadline_certificates_location/$deadline_client_certificate"

# finalize permissions post install:
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/DeadlineDatabase10
sudo chown $deadlineuser_name:$deadlineuser_name /opt/Thinkbox/certs/*
sudo chmod u=wr,g=r,o-rwx /opt/Thinkbox/certs/*
sudo chmod u=wr,g=r,o=r /opt/Thinkbox/certs/ca.crt

# cat /var/lib/Thinkbox/Deadline10/deadline.ini
# [Deadline]
# HttpListenPort=8080
# TlsListenPort=4433
# TlsServerCert=/opt/Thinkbox/certs//deadlinedb.service.consul.pfx
# TlsCaCert=/opt/Thinkbox/certs//ca.crt
# TlsAuth=True
# LaunchRemoteConnectionServerAtStartup=True
# KeepRemoteConnectionServerRunning=True
# LicenseMode=Standard
# LicenseServer=
# Region=
# LauncherListeningPort=17000
# LauncherServiceStartupDelay=60
# AutoConfigurationPort=17001
# SlaveStartupPort=17003
# SlaveDataRoot=
# RestartStalledSlave=false
# NoGuiMode=false
# LaunchSlaveAtStartup=false
# AutoUpdateOverride=
# IncludeRCSInLauncherMenu=true
# ConnectionType=Repository
# NetworkRoot=/opt/Thinkbox/DeadlineRepository10/
# DbSSLCertificate=/opt/Thinkbox/DeadlineDatabase10/certs/Deadline10Client.pfx
# NetworkRoot0=/opt/Thinkbox/DeadlineRepository10/;/opt/Thinkbox/DeadlineDatabase10/certs/Deadline10Client.pfx
# LaunchPulseAtStartup=True
# ProxyRoot=deadlinedb.service.consul:4433
# ProxyUseSSL=True
# ProxySSLCertificate=/opt/Thinkbox/certs/Deadline10RemoteClient.pfx
# ProxyRoot0=deadlinedb.service.consul:4433;/opt/Thinkbox/certs/Deadline10RemoteClient.pfx

# cat /opt/Thinkbox/DeadlineRepository10/settings/connection.ini 
# [Connection]
# AlternatePort=0
# Authenticate=True
# DatabaseName=deadline10db
# DbType=MongoDB
# EnableSSL=True
# Hostname=deadlinedb.service.consul
# PasswordHash=
# Port=27100
# ReplicaSetName=
# SplitDB=False
# Username=
# Version=10
# StorageAccess=Database
# CACertificatePath=

sudo service deadline10launcher restart

echo "Validate that a connection with the database can be established with the config"
sudo /opt/Thinkbox/DeadlineDatabase10/mongo/application/bin/deadline_mongo --eval 'printjson(db.getCollectionNames())'
# /opt/Thinkbox/DeadlineDatabase10/mongo/application/bin/deadline_mongo --sslPEMKeyPassword "avaultpassword" --eval 'printjson(db.getCollectionNames())'

# cd $pwd