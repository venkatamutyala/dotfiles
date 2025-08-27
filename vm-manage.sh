#!/bin/bash

# Virsh Remote Management Utility
#
# This script provides a simple interface to manage remote virtual machines
# using virsh with command-line flags for all parameters.
#
# Usage: ./vm-manage.sh <command> [options] --user <user> --host <host> --key <keyfile>
#
# Example: ./vm-manage.sh list --user root --host server.venkatamutyala.com --port 2222 --key /root/.ssh/id_rsa
#

# --- Function to print usage information and exit ---
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Required Arguments:"
    echo "  --user <user>               Username for the remote host (default: root)."
    echo "  --host <host>               IP address or hostname of the remote host (default: localhost)."
    echo "  --port <port>               SSH port for the remote host (default: 2222)."
    echo "  --key <keyfile_path>        Path to the SSH private key (default: /root/.ssh/id_rsa)."
    echo ""
    echo "Commands & Options:"
    echo "  --name <vm_name>            The name of the virtual machine (required for most commands)."
    echo "  list                        List all virtual machines."
    echo "  status                      Get the status of a virtual machine."
    echo "  start, stop, destroy        Control a virtual machine's state."
    echo "  console                     Get an interactive console to a virtual machine. 🖥️"
    echo "  delete                      Delete a virtual machine and its storage."
    echo "  create                      Create a new VM. Requires --image-url and optional flags:"
    echo "    --image-url <url>         URL of the cloud image for creation."
    echo "    --ram <MB>                Set RAM in megabytes (default: 2048)."
    echo "    --vcpus <count>           Set number of vCPUs (default: 2)."
    echo "    --disk <GB>               Set disk size in gigabytes (default: 20)."
    echo "    --os-variant <variant>    Set OS variant (default: linux2022)."
    echo "    --bridge <bridge_name>    Set network bridge (default: virbr0)."
    echo "    --net-model <model>       Set network model (default: virtio)."
    echo "    --tailscale-authkey <key> Automatically configure Tailscale."
    echo ""
    echo "Example:"
    echo "  $0 create --name my-vm --image-url https://.../image.qcow2 --user root --host localhost --port 2222 --key /root/.ssh/id_rsa"
    exit 1
}

# --- Parse All Arguments ---
# Initialize variables
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PORT=""
KEYFILE_PATH=""
COMMAND=""
VM_NAME=""
IMAGE_URL=""
RAM_MB=2048
VCPUS=2
DISK_SIZE_GB=20
TAILSCALE_AUTHKEY=""
OS_VARIANT="linux2022"
NETWORK_BRIDGE="virbr0"
NETWORK_MODEL="virtio"


# The command is the first positional argument
if [[ $# -eq 0 ]] || [[ "$1" == -* ]]; then
    echo "Error: A command (e.g., list, create, start) is required." >&2
    usage
fi
COMMAND="$1"
shift # Consume the command argument

# Use a while loop to process all arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) REMOTE_USER="$2"; shift 2 ;;
        --host) REMOTE_HOST="$2"; shift 2 ;;
        --port) REMOTE_PORT="$2"; shift 2 ;;
        --key) KEYFILE_PATH="$2"; shift 2 ;;
        --name) VM_NAME="$2"; shift 2 ;;
        --image-url) IMAGE_URL="$2"; shift 2 ;;
        --ram) RAM_MB="$2"; shift 2 ;;
        --vcpus) VCPUS="$2"; shift 2 ;;
        --disk) DISK_SIZE_GB="$2"; shift 2 ;;
        --tailscale-authkey) TAILSCALE_AUTHKEY="$2"; shift 2 ;;
        --os-variant) OS_VARIANT="$2"; shift 2 ;;
        --bridge) NETWORK_BRIDGE="$2"; shift 2 ;;
        --net-model) NETWORK_MODEL="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# --- Set Defaults ---
# Use parameter expansion to set default values only if they are not already set.
REMOTE_USER=${REMOTE_USER:-root}
REMOTE_HOST=${REMOTE_HOST:-localhost}
REMOTE_PORT=${REMOTE_PORT:-2222}
KEYFILE_PATH=${KEYFILE_PATH:-/root/.ssh/id_rsa}

# --- Validate Required Arguments ---
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ] || [ -z "$KEYFILE_PATH" ] || [ -z "$COMMAND" ]; then
    echo "Error: Missing one or more required arguments: a command, --user, --host, --key" >&2
    usage
fi

# Construct the connection string
CONNECTION_STRING="qemu+ssh://${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}/system?keyfile=${KEYFILE_PATH}&no_verify=1"

# --- Helper Functions ---
run_virsh() {
    virsh -c "$CONNECTION_STRING" "$@"
}

# --- Command Functions ---
start_vm() {
    echo "Starting VM: $VM_NAME..."
    run_virsh start "$VM_NAME"
}

stop_vm() {
    echo "Stopping VM: $VM_NAME..."
    run_virsh shutdown "$VM_NAME"
}

destroy_vm() {
    echo "Forcibly destroying VM: $VM_NAME..."
    run_virsh destroy "$VM_NAME"
}

delete_vm() {
    echo "WARNING: This will permanently delete the VM '$VM_NAME' and its disk."
    read -p "Are you sure you want to continue? (y/N) " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting (undefining) VM: $VM_NAME..."
        run_virsh destroy "$VM_NAME" >/dev/null 2>&1
        run_virsh undefine "$VM_NAME" --remove-all-storage
        echo "VM and its storage have been deleted."
    else
        echo "Deletion cancelled."
    fi
}

console_vm() {
    echo "Connecting to console for VM: $VM_NAME..."
    echo "➡️  Use Ctrl+] to exit the console."
    run_virsh console "$VM_NAME"
}

create_vm() {
    # Check if the VM already exists before doing anything else.
    echo "Checking for existing VM named '$VM_NAME'..." >&2
    run_virsh dominfo "$VM_NAME" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Error: A VM named '$VM_NAME' already exists." >&2
        echo "Please choose a different name or use the 'delete' command to remove it first." >&2
        exit 1
    fi
    echo "VM does not exist. Proceeding with creation..." >&2

    local DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
    echo "Downloading fresh base image to ${DISK_PATH} and resizing..." >&2
    
    # Download the image fresh every time and resize it in place.
    ssh -t -p "$REMOTE_PORT" -i "$KEYFILE_PATH" "${REMOTE_USER}@${REMOTE_HOST}" <<EOF
        # Download directly to the final destination using wget
        echo 'Downloading image...' >&2
        sudo wget -q --show-progress -O '${DISK_PATH}' '${IMAGE_URL}' &&
        
        # Resize the new disk in place
        echo 'Resizing new disk to ${DISK_SIZE_GB}G...' >&2
        sudo qemu-img resize '${DISK_PATH}' ${DISK_SIZE_GB}G
EOF
    # Check the exit status of the download/resize ssh command
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download or resize disk on remote host." >&2 && exit 1
    fi

    local CLOUD_INIT_TEMP_FILE=""
    if [ -n "$TAILSCALE_AUTHKEY" ]; then
        CLOUD_INIT_TEMP_FILE=$(mktemp)
        # Use a quoted heredoc ('EOF') here to prevent local expansion of characters like `$`
        cat > "$CLOUD_INIT_TEMP_FILE" <<'EOF'
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
runcmd:
- 'curl -fsSL https://tailscale.com/install.sh | sh'
- ['tailscale', 'up', '--authkey=${TAILSCALE_AUTHKEY}', '--hostname=${VM_NAME}']
- ['tailscale', 'set', '--ssh']
- ['tailscale', 'set', '--accept-routes']
- ['passwd', '-d', 'root']
EOF
        # Now, substitute the variables into the temp file
        sed -i "s/\${VM_NAME}/${VM_NAME}/g" "$CLOUD_INIT_TEMP_FILE"
        sed -i "s/\${TAILSCALE_AUTHKEY}/${TAILSCALE_AUTHKEY}/g" "$CLOUD_INIT_TEMP_FILE"
    fi

    echo "Attempting to create VM with the following parameters:"
    echo "  RAM: ${RAM_MB}MB"
    echo "  vCPUs: ${VCPUS}"
    echo "  Disk: ${DISK_PATH} (${DISK_SIZE_GB}GB)"
    echo "  OS Variant: ${OS_VARIANT}"
    echo "  Network: bridge=${NETWORK_BRIDGE}, model=${NETWORK_MODEL}"
    [ -n "$TAILSCALE_AUTHKEY" ] && echo "  Cloud-Init: Enabled with Tailscale"

    local virt_install_cmd=(virt-install --connect "$CONNECTION_STRING"
        --name "$VM_NAME" --ram "$RAM_MB" --vcpus "$VCPUS"
        --os-variant "$OS_VARIANT"
        --disk "path=$DISK_PATH,format=qcow2,bus=virtio"
        --import --network "bridge=${NETWORK_BRIDGE},model=${NETWORK_MODEL}"
        --graphics none --noautoconsole)

    if [ -n "$TAILSCALE_AUTHKEY" ]; then
        virt_install_cmd+=(--cloud-init "user-data=$CLOUD_INIT_TEMP_FILE")
    fi

    "${virt_install_cmd[@]}"
    
    if [ -n "$CLOUD_INIT_TEMP_FILE" ]; then
        rm "$CLOUD_INIT_TEMP_FILE"
    fi

    if [ $? -eq 0 ]; then
        if [ -z "$TAILSCALE_AUTHKEY" ]; then
            echo ""
            echo "--- IMPORTANT ---"
            echo "No cloud-init configuration was provided."
            echo "The guest OS is not aware of the resized disk space."
            echo "You will need to manually resize the partitions inside the VM."
            echo "-----------------"
        else
            echo "VM creation initiated. Cloud-init will configure the guest on first boot."
        fi
    else
        echo "Error: virt-install command failed." >&2
    fi
}

get_status() {
    echo "Getting status for VM: $VM_NAME..."
    run_virsh dominfo "$VM_NAME"
}

list_vms() {
    echo "Listing all VMs..."
    run_virsh list --all
}

# --- Main Logic ---
case "$COMMAND" in
    start|stop|destroy|delete|status|console)
        [ -z "$VM_NAME" ] && echo "Error: --name is required for the '$COMMAND' command." >&2 && usage
        "${COMMAND}_vm"
        ;;
    create)
        [ -z "$VM_NAME" ] && echo "Error: --name is required for the 'create' command." >&2 && usage
        [ -z "$IMAGE_URL" ] && echo "Error: --image-url is required for the 'create' command." >&2 && usage
        create_vm
        ;;
    list)
        list_vms
        ;;
    *)
        echo "Error: Invalid command '$COMMAND'" >&2
        usage
        ;;
esac

exit 0
