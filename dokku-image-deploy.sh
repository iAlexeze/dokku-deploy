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
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${yellow}WARN: ${reset} $1"
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
IMAGE_NAME="$IMAGE_TAG"

# Internal Variables
SSH_ACCESS_KEY="${SSH_DIR}/${BITBUCKET_CLONE_KEY_NAME}"
APPLICATION_DOMAIN_NAME="${DOMAIN_NAME}"

# Function to add SSH key
function add_ssh_key {
    if ! ssh-add -l > /dev/null 2>&1; then
        echo "Starting ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null 2>&1 || log_error "Failed to start ssh-agent"
    else
        echo "ssh-agent is already running."
    fi

    ssh-add "$SSH_ACCESS_KEY" > /dev/null 2>&1 || log_error "Failed to add SSH key.  \nEnter a BITBUCKET_CLONE_KEY_NAME already added to your bitbucket profile and also located at ~/.ssh in the server"
}

# Function to add SSH key
function add_ssh_key {
    # Add SSH-Key to ssh-agent
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
    echo
    log_success "Cleanup Completed"
}

# Function to check if the app exists
function check_app_exists {

    # Function to create a new Dokku application
    create_app() {
        log_info "Creating $APPLICATION_NAME..."
        dokku apps:create "$APPLICATION_NAME" || log_error "Failed to create application $APPLICATION_NAME"
        log_success "$APPLICATION_NAME created"
    }

    # Function to set domain for the application
    set_app_domain() {
        if [ -n "$APPLICATION_DOMAIN_NAME" ]; then
            dokku domains:set "$APPLICATION_NAME" "$APPLICATION_DOMAIN_NAME" || log_error "Failed to add domain - [$APPLICATION_DOMAIN_NAME] to application [$APPLICATION_NAME]"
            log_success "$APPLICATION_DOMAIN_NAME set to $APPLICATION_NAME"
        else
            log_warn "Domain variable EMPTY. You can set the domain for the application manually using: ${yellow}dokku domains:set <APPLICATION_NAME> <APPLICATION_DOMAIN_NAME> ${reset}"
        fi
    }

    # Main logic to check if the app exists
    if ! dokku apps:list | grep -iq "$APPLICATION_NAME"; then
        log_warn "$APPLICATION_NAME application NOT FOUND!"
        create_app
        set_app_domain
    else
        echo -e "\n--------------------------\nApplication - [$APPLICATION_NAME] already exists.\nProceeding to build...\n--------------------------"
    fi
}

# Function to deploy the app
function deploy_app {
    # Function to handle app deployment
    app_deploy_setup() {   

        # Function to show app info
        show_app_info() {
        # Show report for the app
        dokku ps:report "$APPLICATION_NAME" || log_error "Failed to show app report"
        # Check if the app is running
        if ! docker ps --filter "name=$APPLICATION_NAME" --format "{{.Names}}" | grep -q "$APPLICATION_NAME"; then
            log_error "App is not running"
        else
            log_success "App $APPLICATION_NAME is running"
            docker ps --filter "name=$APPLICATION_NAME"
        fi
        # Deployment status
        echo -e "\n---------------------------------------\n$APPLICATION_NAME Deployment is Successful\n---------------------------------------"

        }
        
        log_info "Deployment run started"

        # Declare temp file to store logs
        TEMP_LOG_FILE="/tmp/dokku_$(date +%s)_$RANDOM"
        # Deploy using the latest image and capture output
        DEPLOY_OUTPUT=$(dokku git:from-image "$APPLICATION_NAME" "$IMAGE_NAME" | tee "$TEMP_LOG_FILE")

        # Check for specific error message indicating image is the same
        if dokku git:from-image "$APPLICATION_NAME" "$IMAGE_NAME" | grep -q "No changes detected, skipping git commit"; then
            log_warn "No changes detected. Rebuilding the app..."
            dokku ps:rebuild "$APPLICATION_NAME" || log_error "Failed to rebuild $APPLICATION_NAME"
            log_success "App Rebuilt successfully"
            show_app_info
            exit 0
        else
            log_error "Failed to deploy $APPLICATION_NAME: $DEPLOY_OUTPUT"
        fi

        # Show application information after deployment
        show_app_info
    }

    # Function to apply a custom certificate
    use_custom_certificate() {
        if [ -n "$CUSTOM_CERT_FILE" ]; then
            if [ -f "$CUSTOM_CERT_FILE" ]; then
                log_info "Applying ${yellow}custom certificate${reset} to $APPLICATION_DOMAIN_NAME..."
                if dokku certs:add "$APPLICATION_NAME" < "$CUSTOM_CERT_FILE"; then
                    log_success "Custom certificate applied successfully!"
                else
                    log_warn "${red}Error adding custom certificate.${reset}"
                    log_info "Apply manually by running: ${yellow}dokku certs:add <APPLICATION_NAME> <CUSTOM_CERT_FILE>${reset}"
                    log_info "${yellow}Custom certificate file${reset} should contain 'server.crt' and 'server.key'"
                fi
            else
                log_warn "${red}Custom certificate file not found: ${CUSTOM_CERT_FILE}${reset}"
                log_info "Please ensure the file exists and is accessible."
            fi
        fi
    }

    # Function to enable Let's Encrypt certificate
    use_letsencrypt_certificate() {
        log_info "Setting up Let's Encrypt SSL Certificate for $APPLICATION_DOMAIN_NAME..."
        if dokku letsencrypt:enable "$APPLICATION_NAME" "$APPLICATION_DOMAIN_NAME"; then
            log_success "SSL Certificate obtained successfully for $APPLICATION_DOMAIN_NAME"
        else
            log_warn "Failed to add Let's Encrypt to $APPLICATION_NAME"
            log_warn "You can set the domain for the application manually using: ${yellow}dokku domains:set <APPLICATION_NAME> <APPLICATION_DOMAIN_NAME>${reset}"
        fi
    }

    # Function to check if Let's Encrypt plugin is installed
    check_letsencrypt_installed() {
        if ! dokku plugin:list | grep -i "letsencrypt"; then
            log_warn "Let's Encrypt plugin NOT FOUND!"
            log_warn "Install Let's Encrypt plugin by running:"
            log_warn "sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git"
        else
            log_success "Let's Encrypt plugin already installed."
            use_letsencrypt_certificate
        fi
    }

    # Function to handle SSL setup
    enable_ssl() {
        if [ -n "$APPLICATION_DOMAIN_NAME" ]; then
            use_custom_certificate
            if [ -z "$CUSTOM_CERT_FILE" ]; then
                check_letsencrypt_installed
            fi
        else
            log_warn "Domain variable EMPTY. You can set the domain for the application manually using: ${yellow}dokku domains:set <APPLICATION_NAME> <APPLICATION_DOMAIN_NAME>${reset}"
        fi
    }

    # Main function to deploy app
    app_deploy_setup
    enable_ssl
}


dokku_app_deploy(){

  add_ssh_key
  check_app_exists
  deploy_app
  cleanup_docker

}

run dokku_app_deploy

if [[ "${status}" == "0" ]]; then
  log_success "Deployment run finished"
else
  log_error "Failed to complete deployment run"
fi
