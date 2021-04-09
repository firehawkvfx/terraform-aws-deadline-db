#!/bin/bash

# This installs certificates with the DB.

set -e

# User vars
installers_bucket="${installers_bucket}"
deadline_version="${deadline_version}"
download_dir="/var/tmp/downloads"

mongo_url="https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1604-3.6.19.tgz"

# Script vars (implicit)
deadline_linux_installers_tar="/tmp/Deadline-${deadline_version}-linux-installers.tar"
deadline_linux_installers_filename="$(basename $deadline_linux_installers_tar)"
deadline_linux_installers_basename="${deadline_linux_installers_filename%.*}"
deadline_installer_dir="$download_dir/$deadline_linux_installers_basename"
mongo_installer_tgz="$download_dir/$(basename $mongo_url)"
deadline_db_installer_filename="DeadlineRepository-${deadline_version}-linux-x64-installer.run"
deadline_client_installer_filename="DeadlineClient-${deadline_version}-linux-x64-installer.run"

# Download mongo
if [[ -f "$mongo_installer_tgz" ]]; then
    echo "File already exists: $mongo_installer_tgz"
else
    wget $mongo_url -O $mongo_installer_tgz
fi
# Download Deadline
if [[ -f "$deadline_linux_installers_tar" ]]; then
    echo "File already exists: $deadline_linux_installers_tar"
else
    # Prefer installation from Thinkbox S3 Bucket for visibility when a version is deprecated.
    output=$(aws s3api head-object --bucket thinkbox-installers --key "Deadline/${deadline_version}/Linux/${deadline_linux_installers_filename}") && exit_status=0 || exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "...Downloading Deadline from: thinkbox-installers"
        aws s3api get-object --bucket thinkbox-installers --key "Deadline/${deadline_version}/Linux/${deadline_linux_installers_filename}" "${deadline_linux_installers_tar}"
        # If this doesn't exist in user bucket, upload it for reproducibility (incase the Thinkbox installer becomes unavailable).
        echo "...Querying if this file exists in $installers_bucket"
        output=$(aws s3api head-object --bucket $installers_bucket --key "$deadline_linux_installers_filename") && exit_status=0 || exit_status=$?
        if [[ ! $exit_status -eq 0 ]]; then
            echo "Uploading the file to $installers_bucket $deadline_linux_installers_filename"
            aws s3api put-object --bucket $installers_bucket --key "$deadline_linux_installers_filename" --body "${deadline_linux_installers_tar}"
        else
            echo "The bucket $installers_bucket already contains: $deadline_linux_installers_filename"
        fi
    else
        printf "\n\nWarning: The installer was not aquired from Thinkbox.  It may have become deprecated.  Other AWS Accounts will not be able to install this version.\n\n"
        echo "...Downloading from: $installers_bucket"
        aws s3api get-object --bucket $installers_bucket --key "$deadline_linux_installers_filename" "${deadline_linux_installers_tar}"
    fi
fi

sudo mkdir -p $deadline_installer_dir

# Extract Installer
sudo tar -xvf $deadline_linux_installers_tar -C $deadline_installer_dir
