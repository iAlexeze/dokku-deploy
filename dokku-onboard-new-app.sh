#!/usr/bin/env bash
#
# Run a command or script on your server
#
# Required globals:
#   SSH_USER
#   SERVER
#   COMMAND
#
# Optional globals:
#   EXTRA_ARGS
#   ENV_VARS
#   APPLICATION_NAME
#   DEBUG (default: "false")
#   MODE (default: "deploy")
#   SSH_KEY (default: null)
#   PORT (default: 22)
#


# Begin Standard 'imports'
set -e
set -o pipefail


gray="\\e[37m"
blue="\\e[36m"
red="\\e[31m"
green="\\e[32m"
yellow="\\e[33m"
reset="\\e[0m"

#######################################
# echoes a message in blue
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
info() { echo -e "${blue}INFO: $*${reset}"; }

#######################################
# echoes a message in red
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
error() { echo -e "${red}ERROR: $*${reset}"; }

#######################################
# echoes a message in grey. Only if debug mode is enabled
# Globals:
#   DEBUG
# Arguments:
#   Message
# Returns:
#   None
#######################################
debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    echo -e "${gray}DEBUG: $*${reset}";
  fi
}

#######################################
# echoes a message in yellow
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
warning() { echo -e "${yellow}✔ $*${reset}"; }

#######################################
# echoes a message in green
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
success() { echo -e "${green}✔ $*${reset}"; }

#######################################
# echoes a message in red and terminates the programm
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
fail() { echo -e "${red}✖ $*${reset}"; exit 1; }

## Enable debug mode.
enable_debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    info "Enabling debug mode."
    set -x
  fi
}

#######################################
# echoes a message in blue
# Globals:
#   status: Exit status of the command that was executed.
#   output_file: Local path with captured output generated from the command.
# Arguments:
#   command: command to run
# Returns:
#   None
#######################################
run() {
  output_file="/var/tmp/pipe-$(date +%s)-$RANDOM"

  echo "$@"
  set +e
  "$@" | tee "$output_file"
  status=$?
  set -e
}

#######################################
# Initialize array variable with the specified name
# https://confluence.atlassian.com/bitbucket/advanced-techniques-for-writing-pipes-969511009.html
# Arguments:
#   array_var: the name of the variable
# Returns:
#   None
#######################################
init_array_var() {
  local array_var=${1}
  local count_var=${array_var}_COUNT
  for (( i = 0; i < ${!count_var:=0}; i++ ))
  do
    eval "${array_var}"[$i]='$'"${array_var}"_${i}
  done
}

#######################################
# Check if a newer version is available and show a warning message
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Message
#######################################
check_for_newer_version() {
  set +e
  if [[ -f "/pipe.yml" ]]; then
    local pipe_name
    local pipe_repository
    local pipe_current_version
    local pipe_latest_version
    local wget_debug_level="--quiet"

    pipe_name=$(awk -F ": " '$1=="name" {print $NF;exit;}' /pipe.yml)
    pipe_repository=$(awk '/repository/ {print $NF}' /pipe.yml)
    pipe_current_version=$(awk -F ":" '/image/ {print $NF}' /pipe.yml)

    if [[ "${DEBUG}" == "true" ]]; then
      warning "Starting check for the new version of the pipe..."
      wget_debug_level="--verbose"
    fi
    pipe_latest_version=$(wget "${wget_debug_level}" -O - "${pipe_repository}"/raw/master/pipe.yml | awk -F ":" '/image/ {print $NF}')      

    if [[ "${pipe_current_version}" != "${pipe_latest_version}" ]]; then
      warning "New version available: ${pipe_name} ${pipe_current_version} to ${pipe_latest_version}"
    fi
  fi
  set -e
}

# End standard 'imports'

DEPLOY_SCRIPT="./dokku_deploy.sh"

info "Executing Deployment...."

enable_debug

# Declare Variables
SSH_DIR='/home/dokku/.ssh'
DEPLOYMENT_DIR='/home/dokku/.deployments'
DATE=$(date +%Y.%m.%d-%H:%M)
IMAGE_NAME="${APPLICATION_NAME}-v1.${DATE}"
CERT_TAR="/home/dokku/.ssl/ssl-eclathealthcare_com/cert-key.tar"

# Internal Variables
SSH_ACCESS_KEY="${SSH_DIR}/${BITBUCKET_CLONE_KEY_NAME}"
PROJ_DIR="${DEPLOYMENT_DIR}/${PROJECT_DIRECTORY_NAME}"
APP_URL="${SUBDOMAIN}.eclathealthcare.com"

# Set Program Name
PROGNAME=$(basename "$0")

# Custom error handling function
function error_exit {
    echo -e "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    info "INFO: Cleaning up due to failure..."
    dokku apps:destroy ${APPLICATION_NAME} --force
    rm -rf ${PROJ_DIR}
    info "Done"
    exit 1
}

# Function to add SSH key
function add_ssh_key {
    if ! ssh-add -l > /dev/null 2>&1; then
        echo "Starting ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null 2>&1 || error_exit "Failed to start ssh-agent"
    else
        echo "ssh-agent is already running."
    fi

    ssh-add "${SSH_ACCESS_KEY}" > /dev/null 2>&1 || error_exit "Failed to add SSH key.  \nEnter a BITBUCKET_CLONE_KEY_NAME already added to your bitbucket profile and also located at ~/.ssh in the server"
}

# Function to clean up unused images and resources
function cleanup_docker {
    echo "Cleaning up unused images and resources..."
    docker system prune -af > /dev/null 2>&1 &

    local prune_pid=$!
    while kill -0 ${prune_pid} 2>/dev/null; do
        echo -n "."
        sleep 1
    done
    echo -e "\nDone!"
}

<<<<<<< HEAD
=======
copy_env_file() {
    if [[ -n "${APP_ENV_FILE}" ]]; then
        info "INFO: env file detected"
        
        if [[ -f "${APP_ENV_FILE}" ]]; then
            info "Copying env file..."
            cp -r "${APP_ENV_FILE}" "${PROJ_DIR}/.env" || error_exit "Failed to copy ${APP_ENV_FILE} to ${PROJ_DIR}"
            success "${APP_ENV_FILE} updated"
        else
            info "Env file ${APP_ENV_FILE} does not exist."
        fi
    else
        info "No env file provided."
    fi
}

>>>>>>> 98722bf (hello revert)
# Function to deploy the app
function deploy_app {
    # Change to project directory
    cd "${PROJ_DIR}" || error_exit "Failed to change directory to ${PROJ_DIR}"

    # Pull latest changes
    git pull origin ${BRANCH} || error_exit "Failed to pull latest changes"

    # Switch to the deployment branch
    git switch ${BRANCH} || error_exit "Failed to switch to deployment branch"

    # Build Docker image
    docker build -t "${IMAGE_NAME}" . || error_exit "Failed to build ${APPLICATION_NAME} image"

    # Deploy using the latest image
    dokku git:from-image "${APPLICATION_NAME}" "${IMAGE_NAME}" || error_exit "Failed to deploy ${APPLICATION_NAME}"

    # Show report for the app
    dokku ps:report "${APPLICATION_NAME}" || error_exit "Failed to show app report"

    # Check if app is running
    if ! docker ps --filter "name=${APPLICATION_NAME}" --format "{{.Names}}" | grep -q "${APPLICATION_NAME}"; then
        error_exit "App is not running"
    else
        echo "App ${APPLICATION_NAME}" is running
        docker ps --filter "name=${APPLICATION_NAME}"
    fi

    # Deployment status
    echo -e "\n---------------------------------------\n${APPLICATION_NAME} Deployment is Successful\n---------------------------------------"
}

function create_app {
    info "INFO: Creating app - ${APPLICATION_NAME}..."

    # Create Application
    dokku apps:create ${APPLICATION_NAME} || error_exit "Failed to create app - ${APPLICATION_NAME}"
    success "${APPLICATION_NAME} created"

    # Add domain name to the application
    info "Adding Domain Name to ${APPLICATION_NAME}..."
    dokku domains:set ${APPLICATION_NAME} ${APP_URL} || error_exit "Failed to add App URL to ${APPLICATION_NAME}"
    success "${APP_URL} added to ${APPLICATION_NAME} successfully"

    # Remove default URL from the application
    info "Removing Default Domain Name from ${APPLICATION_NAME}..."
    # dokku domains:remove ${APPLICATION_NAME} ${APPLICATION_NAME}.* || error_exit "Failed to remove default App URL from ${APPLICATION_NAME}"
    success "Default Domains removed successfully"

    # Setup Application Repository Remotely
    cd ${DEPLOYMENT_DIR} || error_exit "Failed to change directory to ${DEPLOYMENT_DIR}"
    
    # Check if either the project directory or application directory does not exist
    if [[ ! -d ${PROJECT_DIRECTORY_NAME} ]] || [[ ! -d ${APPLICATION_NAME} ]]; then
       echo "Directory ${PROJECT_DIRECTORY_NAME} or ${APPLICATION_NAME} does not exist. Cloning repository..."
       git clone -b ${BRANCH} git@bitbucket.org:interswitch/${PROJECT_DIRECTORY_NAME} || error_exit "Failed to clone ${PROJECT_DIRECTORY_NAME} Repository"
       success "${PROJECT_DIRECTORY_NAME} cloned successfully"

       # Copy env file into repository if needed during build time
        if [[ -n "${APP_ENV_FILE}" ]]; then
            info "INFO: env file detected"
            
            if [[ -f "${APP_ENV_FILE}" ]]; then
                info "Copying env file..."
                cp -r "${APP_ENV_FILE}" "${PROJ_DIR}/.env" || error_exit "Failed to copy ${APP_ENV_FILE} to ${PROJ_DIR}"
                success "Env file updated"
            else
                info "Env file ${APP_ENV_FILE} does not exist."
            fi
        else
            info "No env file provided."
        fi
    else
       info "INFO: ${PROJECT_DIRECTORY_NAME} repository already on machine"
       info "INFO: Continue to deploy..."
    fi

    # Deploy the Application
    deploy_app

    # Add Certificate to the app_url
    info "INFO: Adding Certificate to ${SUBDOMAIN} ..."
    dokku certs:add ${APPLICATION_NAME} < ${CERT_TAR} || error_exit "Failed to add App Certificate to ${APPLICATION_NAME}"
    success "Certificate added successfully"

    # Check if port mapping is needed
    if [[ -n "${APP_PORT}" ]]; then
            info "INFO: App port detected"

        if [[ ! ${APP_PORT} = "80" ]]; then
            info "INFO: Mapping ports appropriately"
            dokku ports:add ${APPLICATION_NAME} http:80:${APP_PORT} || error_exit "Failed to add Port 80 to ${APPLICATION_NAME}"
            # dokku ports:add ${APPLICATION_NAME} http:443:${APP_PORT} || error_exit "Failed to add Port 443 to ${APPLICATION_NAME}"    
            success "Ports mapped successfully"
        fi
    else
        info "-------------------------------------------------------------------------------------------"
    fi
}

# Separate Deployment Functions
dokku_app_deploy(){
  deploy_app
  cleanup_docker
}

dokku_app_create(){
    create_app
    cleanup_docker
}

# Function to check if the app exists
check_app_exists() {
    if dokku apps:list | grep -iq "$APPLICATION_NAME"; then
        echo "--------------------------"
	success "Application - [$APPLICATION_NAME] already exists."
 	echo "Proceeding to build..."
  	echo "--------------------------"
        dokku_app_deploy
    else
        info "WARN: ${APPLICATION_NAME} NOT FOUND"
        dokku_app_create
        success "${APPLICATION_NAME} created successfully"
    fi
}

# Main script execution
add_ssh_key
run check_app_exists

if [[ "${status}" == "0" ]]; then
  success "Success!"
else
  fail "Error!"
fi
