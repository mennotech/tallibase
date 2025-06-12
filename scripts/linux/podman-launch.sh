#!/bin/bash

# Parse parameters
show_help() {
    echo "Usage: $0 [create|update|delete] --site-name <site_name>"
    echo ""
    echo "  create   Create a new pod and container for the site"
    echo "  update   Update the container image and recreate the container"
    echo "  delete   Remove the existing pod and container for the site"
    echo ""
    echo "Required:"
    echo "  -s, --site-name         Unique site name (e.g. my-site)"
    echo ""
    echo "Options:"
    echo "  -p, --local-port        Local port to use when creating new pod (default: 8080)"
    echo "  -d, --root-domain       Root domain (default: tallibase.io)"
    echo "  -f, --root-folder       Root folder for the site data (default: ~/tallibase)"
    echo "  -r, --rev-tag           Revision tag for the container image (default: latest)"
    echo "  -i, --image             Container image to use (default: docker.io/mennotech/tallibase)"
    echo "  -l, --localhost         Use localhost as the root domain (default: false)"
    echo "  -h, --help              Show this help message and exit"
    echo "  -D, --delete-data       Delete all data associated with the site (default: false)"
    echo "  -P, --pull-image        Pull the latest image before creating the container (default: false)"
    echo ""
}

# Initialize variables
SITE_NAME=""
ACTION=""
ROOT_DOMAIN="tallibase.io"
LOCAL_PORT="8080"
REV_TAG="latest"
ROOT_FOLDER="${HOME}/tallibase"
UPDATE_IMAGE=false
IMAGE="docker.io/mennotech/tallibase"
DELETE_DATA=false
UPDATE_IMAGE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        create)
            ACTION="create"
            shift
            ;;
        update)
            ACTION="update"            
            shift
            ;;
        delete)
            ACTION="delete"
            shift
            ;;
        -d|--root-domain)
            ROOT_DOMAIN="$2"
            shift 2
            ;;
        -s|--site-name)
            SITE_NAME="$2"
            shift 2
            ;;
        -p|--local-port)
            LOCAL_PORT="$2"
            shift 2
            ;;
        -r|--rev-tag)
            REV_TAG="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -l|--localhost)
            ROOT_DOMAIN="localhost"
            shift
            ;;
        -f|--root-folder)
            ROOT_FOLDER="$2"
            shift 2
            ;;
        -D|--delete-data)
            DELETE_DATA=true
            shift
            ;;
        -P|--pull-image)
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

#If no action is specified, print help and exit
if [[ -z "$ACTION" ]]; then
    echo "Error: No action specified. Please use 'create', 'update', or 'delete'."
    show_help
    exit 1
fi

# Check site name
if [[ -z "$SITE_NAME"  ]]; then
    echo "Error: Please provide a site name."
    show_help
    exit 1
fi

# If action is create, check if local port is specified
if [[ "$ACTION" == "create" && -z "$LOCAL_PORT" ]]; then
    echo "Error: Please provide a local port using -p or --local-port."
    show_help
    exit 1
fi


# Convert parameters to lowercase
ROOT_DOMAIN=$(echo "$ROOT_DOMAIN" | tr '[:upper:]' '[:lower:]')
SITE_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]')

POD_NAME="${ROOT_DOMAIN}-${SITE_NAME}"
CONTAINER_NAME="${ROOT_DOMAIN}-${SITE_NAME}-web"

if [[ "$ROOT_DOMAIN" == "localhost" ]]; then
    FQDN="localhost"
else
    FQDN="${SITE_NAME}.${ROOT_DOMAIN}" 
fi


echo "Action: $ACTION"
echo "Full Site Name: $FQDN"
echo ""


# Function to check if a port is available
check_port_available() {
    local port=$1

    # Check if nc is installed
    if ! command -v nc &> /dev/null; then
        echo "Error: 'nc' (netcat) command is not installed. Please install it to check port availability."
        exit 1
    fi

    if ! nc -z localhost "$port"; then
        echo "Port $port is available."
    else
        echo "Port $port is already in use. Please choose a different port."
        exit 1
    fi
}



# Function create pod and container
create_container() {
    # Check if the container already exists
    if podman container exists "$CONTAINER_NAME"; then
        echo "Container '$CONTAINER_NAME' already exists. Select update if you want to update the container."
        exit 0
    fi

    echo "Creating container '$CONTAINER_NAME' in pod '$POD_NAME'..."
    
    # Check if the root folder exists, if not create it
    if [ ! -d "$ROOT_FOLDER/$SITE_NAME" ]; then
        echo "Creating root folder: $ROOT_FOLDER/$SITE_NAME"
        mkdir -p "$ROOT_FOLDER/$SITE_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to create root folder: $ROOT_FOLDER/$SITE_NAME"
            exit 2
        fi
    fi
    podman run -dt --pod "$POD_NAME" --name "$CONTAINER_NAME" --restart=on-failure -e SITENAME="$FQDN" -v "$ROOT_FOLDER/$SITE_NAME/:/opt/drupal/data" "tallibase:$REV_TAG"

    # Check if the container was created successfully
    podman container exists "$CONTAINER_NAME"
    if [ $? -ne 0 ]; then
        echo "Container '$CONTAINER_NAME' does not exist after creation."
        exit 6
    fi 

    # Check if the container is running
    podman ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
    if [ $? -ne 0 ]; then
        echo "Container '$CONTAINER_NAME' is not running after creation."
        exit 6
    fi
    echo "Container '$CONTAINER_NAME' created and started successfully in pod '$POD_NAME'."
    
}

# Function to create systemd service and start service
create_service() {
    # Check if running with permission to create service
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root to create a systemd service."
        exit 1
    fi

    podman generate systemd --new --name "$CONTAINER_NAME" > "/etc/systemd/system/$CONTAINER_NAME.service"
    systemctl enable "$CONTAINER_NAME.service"
    
    # Check if the systemd service was created and started successfully
    if [ $? -ne 0 ]; then
        echo "Failed to create systemd service for container: $CONTAINER_NAME"
        exit 5
    fi
    echo "Systemd service for container '$CONTAINER_NAME' created successfully."
    exit 0
}

# Function to pull the latest image
pull_image() {
    echo "Pulling the latest image: tallibase:$REV_TAG"
    podman pull $IMAGE:$REV_TAG -q
    if [ $? -ne 0 ]; then
        echo "Failed to pull the latest image: tallibase:$REV_TAG"
        echo "To add Docker Hub as a registry in Podman, you need to edit the /etc/containers/registries.conf file and add unqualified-search-registries = [\"docker.io\"]"
        exit 1
    fi
    echo "Image pulled successfully."
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
        podman rm -f "$CONTAINER_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to remove container: $CONTAINER_NAME"
            exit 5
        fi
    else
        echo "Container '$CONTAINER_NAME' does not exist. Nothing to remove."
    fi
}

# Function to delete the pod
delete_pod() {
    # Check if the pod exists and remove it
    if podman pod exists "$POD_NAME"; then
        echo "Pod '$POD_NAME' exists. Removing it..."
        podman pod rm -f "$POD_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to remove pod: $POD_NAME"
            exit 3
        fi
        echo "Pod '$POD_NAME' removed successfully."
    else
        echo "Pod '$POD_NAME' does not exist. Nothing to remove."
    fi
}

# Function to delete data associated with the site
delete_data() {
    if [ "$DELETE_DATA" = true ]; then
        echo "Deleting data associated with the site..."
        if [ -d "$ROOT_FOLDER/$SITE_NAME" ]; then
            rm -rf "$ROOT_FOLDER/$SITE_NAME"
            if [ $? -ne 0 ]; then
                echo "Failed to delete data for site: $SITE_NAME"
                exit 7
            fi
            echo "Data for site '$SITE_NAME' deleted successfully."
        else
            echo "No data found for site '$SITE_NAME'. Nothing to delete."
        fi
    else
        echo "Skipping data deletion as --delete-data is not set."
    fi
}

# Function to delete systemd service file
delete_service() {
    # Check if running with permission to delete service
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root to delete a systemd service."
        exit 1
    fi

    echo "Removing systemd service for container '$CONTAINER_NAME'..."
    if [ -f "/etc/systemd/system/$CONTAINER_NAME.service" ]; then
        if systemctl is-active --quiet "$CONTAINER_NAME.service"; then
            echo "Stopping and disabling service '$CONTAINER_NAME.service'..."
            systemctl stop "$CONTAINER_NAME.service"
            systemctl disable "$CONTAINER_NAME.service"
        fi
    rm -f "/etc/systemd/system/$CONTAINER_NAME.service"
    else
        echo "No systemd service file found for container '$CONTAINER_NAME'. Nothing to remove."
        return 0
    fi

    echo "Systemd service for container '$CONTAINER_NAME' removed successfully."
}

# function to create the pod if it does not exist
create_pod() {
    # Check if the pod already exists
    if podman pod exists "$POD_NAME"; then
        echo "Pod '$POD_NAME' already exists."
        return 0
    else
        # Check if the requested local port is available
        check_port_available "$LOCAL_PORT"

        echo "Creating pod '$POD_NAME'..."
        podman pod create --name "$POD_NAME" -p $LOCAL_PORT:80
        if [ $? -ne 0 ]; then
            echo "Failed to create pod: $POD_NAME"
            exit 4
        fi
        echo "Pod '$POD_NAME' created successfully."
    fi
}



case "$ACTION" in
    "create")
        if [ $UPDATE_IMAGE = true ]; then
            pull_image
        fi
        create_pod
        create_container
        create_service
        exit 0
        ;;
    "update")
        # Check if the pod already exists
        if podman pod exists "$POD_NAME"; then
            pull_image
            kill_container
            create_container
        else
            echo "Pod '$POD_NAME' does not exist."
        fi
        exit 0
        ;;
    "delete")
        kill_container
        delete_pod
        delete_service
        delete_data
        exit 0
        ;;    
    *)
        # If the action is not recognized, print help and exit
        show_help
        echo "Invalid action specified. Use 'create', 'update', or 'delete'."
        exit 1
        ;;
esac
