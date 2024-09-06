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

# Colors
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
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${blue}INFO: ${reset} $1"
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
log_warn() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${yellow}INFO: ${reset} $1"
}

#######################################
# echoes a message in green
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${green}SUCCESS: ✔${reset} $1"
}

#######################################
# echoes a message in red
# Globals:
#   None
# Arguments:
#   Message
# Returns:
#   None
#######################################
# Set Program Name
PROGNAME=$(basename "$0")

# Custom error handling function
log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${red}ERROR ✖${reset} ${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

#######################################
# echoes a message in grey. Only if debug mode is enabled
# Globals:
#   DEBUG
# Arguments:
#   Message
# Returns:
#   None
#######################################
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

DEPLOY_SCRIPT="./dokku_deploy.sh"

log_info "Executing Deployment...."

enable_debug

# Declare Variables
SSH_DIR='/home/dokku/.ssh'
DEPLOYMENT_DIR='/home/dokku/.deployments'
DATE=$(date +%Y.%m.%d-%H:%M)
IMAGE_NAME="$APPLICATION_NAME-v1.$DATE"

# Internal Variables
SSH_ACCESS_KEY="${SSH_DIR}/${BITBUCKET_CLONE_KEY_NAME}"
PROJ_DIR="${DEPLOYMENT_DIR}/${PROJECT_DIRECTORY_NAME}"
APPLICATION_REPO="git@bitbucket.org:interswitch"
REPO_URL="${APPLICATION_REPO}/${PROJECT_DIRECTORY_NAME}"
APPLICATION_DOMAIN_NAME="${DOMAIN_NAME}"

# Function to add SSH key
function add_ssh_key {
    if ! ssh-add -l > /dev/null 2>&1; then
        log_info "Starting ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null 2>&1 || log_error "Failed to start ssh-agent"
    else
        log_info "ssh-agent is already running."
    fi

    ssh-add "$SSH_ACCESS_KEY" > /dev/null 2>&1 || log_error "Failed to add SSH key.  \nEnter a BITBUCKET_CLONE_KEY_NAME already added to your bitbucket profile and also located at ~/.ssh in the server"
}

# Function to clean up unused images and resources
function cleanup_docker {
    log_warn "Cleaning up unused images and resources..."
    docker system prune -af > /dev/null 2>&1 &

    local prune_pid=$!
    while kill -0 $prune_pid 2>/dev/null; do
        echo -n "."
        sleep 1
    done
    log_info "\n\nDone!"
}

# Function to check if the app exists
function check_app_exists {
    if ! dokku apps:list | grep -iq "$APPLICATION_NAME"; then
        log_info "$APPLICATION_NAME NOT FOUND! \nCreating $APPLICATION_NAME..."
        dokku app:create $APPLICATION_NAME || log_error "Failed to create application $APPLICATION_NAME"
        dokku domains:set $APPLICATION_NAME $APPLICATION_DOMAIN_NAME || log_error "Failed to add domain - [$APPLICATION_DOMAIN_NAME] to application [$APPLICATION_NAME]"
    else
        log_info "--------------------------\nApplication - [$APPLICATION_NAME] already exists.\nProceeding to build...\n--------------------------"
    fi
}

# Function to deploy the app
function deploy_app {
    # Function to check if the app is ready to deploy
    ready_to_deploy() {
        # Change to the project directory
        cd "$PROJ_DIR" || log_error "Failed to change directory to $PROJ_DIR"

        # Pull latest changes
        git pull origin $BRANCH || log_error "Failed to pull latest changes"

        # Switch to the deployment branch
        git switch $BRANCH || log_error "Failed to switch to deployment branch"

        # Build Docker image
        docker build -t "$IMAGE_NAME" . || log_error "Failed to build $APPLICATION_NAME image"

        # Deploy using the latest image
        dokku git:from-image "$APPLICATION_NAME" "$IMAGE_NAME" || log_error "Failed to deploy $APPLICATION_NAME"

        # Show report for the app
        dokku ps:report "$APPLICATION_NAME" || log_error "Failed to show app report"

        # Check if the app is running
        if ! docker ps --filter "name=$APPLICATION_NAME" --format "{{.Names}}" | grep -q "$APPLICATION_NAME"; then
            log_error "App is not running"
        else
            log_info "App $APPLICATION_NAME is running"
            docker ps --filter "name=$APPLICATION_NAME"
        fi

        # Deployment status
        log_success "\n---------------------------------------\n$APPLICATION_NAME Deployment is Successful\n---------------------------------------"
    }

    # Function to check the deployment directory
    check_deployment_dir() { 
        if [[ -d $DEPLOYMENT_DIR ]]; then
            cd $DEPLOYMENT_DIR || log_error "Failed to change directory to $DEPLOYMENT_DIR"
            if [[ ! -d $PROJ_DIR ]]; then          
                log_warn "Project Directory $PROJ_DIR NOT FOUND!"
                log_info "Creating Project Directory"
                git clone -b $BRANCH $REPO_URL || log_error "Failed to clone $PROJECT_DIRECTORY_NAME to $PROJ_DIR"
                ready_to_deploy
            else
                # If project directory exists, proceed to deploy
                ready_to_deploy
            fi
        else
            # Create deployment directory if it doesn't exist
            mkdir -p $DEPLOYMENT_DIR || log_error "Failed to make directory - $DEPLOYMENT_DIR"
            check_deployment_dir  # Recursive call to recheck the created directory
        fi
    }

    # Start deployment check
    check_deployment_dir
}


dokku_app_deploy(){

  add_ssh_key
  check_app_exists
  deploy_app
  cleanup_docker

}

run dokku_app_deploy

if [[ "${status}" == "0" ]]; then
  log_success
else
  log_error
fi
