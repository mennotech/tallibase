#!/bin/bash

# Parse parameters
show_help() {
    echo "Usage: $0 --root-domain <root_domain> --site-name <site_name> --local-port <local_port>"
    echo ""
    echo "Required parameters:"
    echo "  -d, --root-domain   Root domain (e.g., tallibase.io)"
    echo "  -s, --site-name     Unique site name"
    echo "  -p, --local-port    Local port to use"
    echo ""
    echo "Optional parameters:"
    echo "  -u --update-image   Download the latest container image"
    echo "  -r, --rev-tag       Revision tag for the container image (default: latest)"
    echo "  -h, --help          Show this help message and exit"
}

# Initialize variables
ROOT_DOMAIN=""
SITE_NAME=""
LOCAL_PORT=""
REV_TAG="latest"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--root-domain)
            ROOT_DOMAIN="$2"
            shift
            ;;
        -s|--site-name)
            SITE_NAME="$2"
            shift
            ;;
        -p|--local-port)
            LOCAL_PORT="$2"
            shift
            ;;
        -r|--rev-tag)
            REV_TAG="$2"
            shift
            ;;
        -u|--update-image)
            UPDATE_IMAGE=true            
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check for required parameters
if [[ -z "$ROOT_DOMAIN" || -z "$SITE_NAME" || -z "$LOCAL_PORT" ]]; then
    echo "Error: Please provide all required parameters."
    show_help
    exit 1
fi


POD_NAME="${$ROOT_DOMAIN}-${SITE_NAME}"
CONTAINER_NAME="${$ROOT_DOMAIN}-${SITE_NAME}-web"
FQDN="${SITE_NAME}.${ROOT_DOMAIN}" 
echo "Pod Name: $POD_NAME"
echo "Container Name: $CONTAINER_NAME"
echo "Site Name: $SITE_NAME"
echo "FQDN: $FQDN"
echo "Local Port: $LOCAL_PORT"


# Function to check if a port is available
check_port_available() {
    local port=$1
    if ! nc -z localhost "$port"; then
        echo "Port $port is available."
    else
        echo "Port $port is already in use. Please choose a different port."
        exit 1
    fi
}



# Function create pod and container
create_container() {
    echo "Creating container '$CONTAINER_NAME' in pod '$POD_NAME'..."    
    podman run -dt --pod "$POD_NAME" --name "$CONTAINER_NAME" -e SITENAME="$FQDN" -v $ROOT_FOLDER/$SITE_NAME/:/opt/drupal/data tallibase:$REV_TAG
    
    if [ $? -ne 0 ]; then
        echo "Failed to create container: $CONTAINER_NAME in pod: $POD_NAME"
        exit 6
    fi
    echo "Container '$CONTAINER_NAME' created successfully."
    exit 0
}

# Function to stop and remove the container then recreate it
kill_container() {
    # Check if the container exists and stop it if running
    if podman ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '$CONTAINER_NAME' is running. Stopping it..."
        podman stop "$CONTAINER_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to stop container: $CONTAINER_NAME"
            exit 5
        fi
    fi
    
    # Remove the existing container
    if podman container exists "$CONTAINER_NAME"; then
        echo "Container '$CONTAINER_NAME' exists. Removing it..."
    fi
    podman rm -f "$CONTAINER_NAME"
    if [ $? -ne 0 ]; then
        echo "Failed to remove container: $CONTAINER_NAME"
        exit 5
    fi
}


# Check if the requested local port is available
check_port_available "$LOCAL_PORT"


# Check if the pod already exists
if podman pod exists "$POD_NAME"; then
    if [ "$UPDATE_IMAGE" = true ]; then
        echo "Pod '$POD_NAME' already exists. Updating container image..."
        podman pull tallibase:$REV_TAG
        if [ $? -ne 0 ]; then
            echo "Failed to pull the latest image: tallibase:$REV_TAG"
            exit 1
        fi
        echo "Image updated successfully. Recreating container..."
        kill_container
        create_container
    else
        echo "Pod '$POD_NAME' already exists. No update performed."
    fi
    
else
    echo "Pod '$POD_NAME' does not exist. Creating new pod..."
    podman pod create --name "$POD_NAME" -p $LOCAL_PORT:80
    if [ $? -ne 0 ]; then
        echo "Failed to create pod: $POD_NAME"
        exit 4
    fi
    create_container
fi