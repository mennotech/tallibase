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
    echo "  -f, --root-folder       Root folder for the site data (default: /root/tallibase)"
    echo "  -r, --rev-tag           Revision tag for the container image (default: latest)"
    echo "  -h, --help              Show this help message and exit"
}

# Initialize variables
SITE_NAME=""
ACTION=""
ROOT_DOMAIN="tallibase.io"
LOCAL_PORT="8080"
REV_TAG="latest"
ROOT_FOLDER="/root/tallibase"
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
        -f|--root-folder)
            ROOT_FOLDER="$2"
            shift 2
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
FQDN="${SITE_NAME}.${ROOT_DOMAIN}" 

echo "Action: $ACTION"
echo "Full Site Name: $FQDN"
echo ""


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
    # Check if the root folder exists, if not create it
    if [ ! -d "$ROOT_FOLDER/$SITE_NAME" ]; then
        echo "Creating root folder: $ROOT_FOLDER/$SITE_NAME"
        mkdir -p "$ROOT_FOLDER/$SITE_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to create root folder: $ROOT_FOLDER/$SITE_NAME"
            exit 2
        fi
    fi
    podman run -dt --pod "$POD_NAME" --name "$CONTAINER_NAME" -e SITENAME="$FQDN" -v "$ROOT_FOLDER/$SITE_NAME/:/opt/drupal/data" "tallibase:$REV_TAG"

    
    if [ $? -ne 0 ]; then
        echo "Failed to create container: $CONTAINER_NAME in pod: $POD_NAME"
        exit 6
    fi
    echo "Container '$CONTAINER_NAME' created successfully."
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



case "$ACTION" in
    "create")
        # Check if the pod already exists
        if podman pod exists "$POD_NAME"; then            
            echo "Pod '$POD_NAME' already exists. Updating container..."            
        else
            # Check if the requested local port is available
            check_port_available "$LOCAL_PORT"
            podman pod create --name "$POD_NAME" -p $LOCAL_PORT:80
            if [ $? -ne 0 ]; then
                echo "Failed to create pod: $POD_NAME"
                exit 4
            fi            
            create_container
        fi
        exit 0
        ;;
    "update")
        # Check if the pod already exists
        if podman pod exists "$POD_NAME"; then
            podman pull tallibase:$REV_TAG -q
            if [ $? -ne 0 ]; then
                echo "Failed to pull the latest image: tallibase:$REV_TAG"
                exit 1
            fi
            echo "Image updated successfully. Recreating container..."
            kill_container
            create_container
        else
            echo "Pod '$POD_NAME' does not exist."
        fi
        exit 0
        ;;
    "delete")
        # Check if the pod exists and remove it
        if podman pod exists "$POD_NAME"; then
            
            echo "Removing container '$CONTAINER_NAME'..."
            kill_container
            
            echo "Removing pod '$POD_NAME'..."
            podman pod rm -f "$POD_NAME"
            if [ $? -ne 0 ]; then
                echo "Failed to remove pod: $POD_NAME"
                exit 3
            fi
            echo "Pod '$POD_NAME' removed successfully."
        else
            echo "Pod '$POD_NAME' does not exist. Nothing to delete."
        fi
        exit 0
        ;;    
    *)
        # If the action is not recognized, print help and exit
        show_help
        echo "Invalid action specified. Use 'create', 'update', or 'delete'."
        exit 1
        ;;
esac
