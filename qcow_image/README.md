## Convert QCOW disk image into VHD

This series of scripts will take a QCOW disk image, convert it to the VHD format used on Citrix XenServer (the hypervisor used on Rackspace's Public Cloud) and then upload it to Rackspace's Cloud Images for usage on the Public Cloud

  __Assumes__: Ubuntu 12.04 bare-metal machine

## Usage

  1. Prep the host

     ```
     apt-get update
     apt-get purge -y nano
     apt-get install -y git vim tmux fail2ban build-essential libffi-dev qemu-utils
     curl --silent https://bootstrap.pypa.io/get-pip.py > /opt/get-pip.py
     python /opt/get-pip.py pip==9.0.1 setuptools==33.1.1 wheel==0.29.0
     pip install six swiftly
     ```

  2. Install the conversion tooling

    * Pulls Xen 4.4.0 source and *only* compiles the tools sub-directory
    * The tools subdirectory contains the `vhd-util` utility used to convert a RAW disk image into VHD format

    ```
    ./compile_vhdutil.sh
    ```

  2. Modify the qcow image

    * Will download Ubuntu 16.04.2 QCOW image if an image is not provided
    * Mounts the QCOW
    * Bootstraps the image with the necessary modifications needed for the Rackspace Public Cloud (via chroot)
    * Unmounts the QCOW

    ```
    # modify_qcow.sh <optional qcow image>
    ./modify_qcow.sh
    ```

  3. Convert the qcow image to vhd

    * Converts the QCOW to RAW
    * Then, converts the RAW image into VHD

    ```
    # qcow_to_vhd.sh <qcow input file> <output directory>
    ./qcow_to_hvd.sh ubuntu-16.04.2-server-cloudimg-amd64-disk1.img .
    ```

  4. Upload to cloudfiles

     ```
     # Setup the swiftly configuration
     source openrc
     echo "[swiftly]" > .swiftly.conf
     echo "auth_user = ${OS_USERNAME}" >> .swiftly.conf
     echo "auth_key = ${OS_PASSWORD}" >> .swiftly.conf
     echo "auth_url = ${OS_AUTH_URL}" >> .swiftly.conf
     echo "region = ${OS_REGION_NAME}" >> .swiftly.conf

     # Upload the image
     CLOUDFILES_CONTAINER="images"
     IMAGE_FILENAME="ubuntu-16.04.2-server-cloudimg-amd64-disk1.vhd"
     swiftly put -i ${IMAGE_FILENAME} ${CLOUDFILES_CONTAINER}/${IMAGE_FILENAME}
     ```

  5. Import the cloudfiles image into the image service

     ```
     source openrc
     CLOUDFILES_CONTAINER="images"
     IMAGE_FILENAME="ubuntu-16.04.2-server-cloudimg-amd64-disk1.vhd"
     IMAGE_DESCRIPTION="Ubuntu 16.04.2 LTS prepared for RPC deployment"
     ./image_import.sh ${CLOUDFILES_CONTAINER} ${IMAGE_FILENAME} "${IMAGE_DESCRIPTION}"
     ```

  5. Wait until the import completes successfully

     ```
     # Set the job ID (use the 'id' value from the previous script output
     JOB_ID=<uuid value>

     # Set the crendentials appropriately
     source openrc

     # Grab an auth token
     export TOKEN=`curl https://identity.api.rackspacecloud.com/v2.0/tokens -X POST -d '{ "auth":{"RAX-KSKEY:apiKeyCredentials": { "username":"'${OS_USERNAME}'", "apiKey": "'${OS_PASSWORD}'" }} }' -H "Content-type: application/json" |  python -mjson.tool | grep -A5 token | grep id | cut -d '"' -f4`

     # configure the endpoint to use
     export IMPORT_IMAGE_ENDPOINT=https://${OS_REGION_NAME}.images.api.rackspacecloud.com/v2/${OS_TENANT_NAME}

     # Check the job status
     curl "$IMPORT_IMAGE_ENDPOINT/tasks/${JOB_ID}" -H "X-Auth-Token: $TOKEN" -H "Content-Type: application/json" | python -mjson.tool
     ```

  6. Boot VM with new image

     ```
     nova boot --image="${IMAGE_DESCRIPTION}" --flavor=general1-8 mytestserver1
     ```
