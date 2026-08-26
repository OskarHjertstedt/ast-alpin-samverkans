#!/bin/bash
#############################################################################
# UNIVERSAL DEPLOYMENT SCRIPT TEMPLATE
# 
# This is a template for deploy.sh in each site directory.
# Copy this file to your site and customize the CONFIGURATION section below.
# 
# Usage:   ./deploy.sh [OPTIONS] [VERSION] [DESCRIPTION]
# Options: --fast, --no-check, --dry-run, --rollback, --status
# 
# Examples:
#   ./deploy.sh                              # Auto-bump version, deploy, verify health
#   ./deploy.sh 1.2.3 "Fixed bug X"         # Deploy with custom version + message
#   ./deploy.sh --fast                       # Skip health checks (use with caution)
#   ./deploy.sh --rollback                   # Rollback to previous version
#   ./deploy.sh --status                     # Show current status
#############################################################################

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION - Customize these for your site
# ═══════════════════════════════════════════════════════════════════════════

# Service name (should match directory name and docker-compose service)
SERVICE_NAME="astalpin.se"

# Docker Compose services to check (space-separated)
# Example: "frontend api database"
DOCKER_SERVICES="app "

# Health check URL (empty to skip)
# Example: "http://localhost:3000/health"
HEALTH_CHECK_URL=""

# Health check port if above URL not available
HEALTH_CHECK_PORT=""

# Compose file name for this site
COMPOSE_FILE_NAME="docker-compose.yml"

# Site-specific environment variables (optional)
# CUSTOM_ENV_VAR="value"

# ═══════════════════════════════════════════════════════════════════════════
# STANDARD CONFIGURATION - Don't change these
# ═══════════════════════════════════════════════════════════════════════════

REMOTE_HOST="${REMOTE_HOST:-192.168.50.7}"
REMOTE_USER="${REMOTE_USER:-ubuntu}"
REMOTE_PATH="/home/ubuntu/docker/${SERVICE_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Path to shared library (one level up)
DEPLOY_LIB="${PARENT_DIR}/_deploy_lib.sh"
if [[ ! -f "$DEPLOY_LIB" ]]; then
    echo "ERROR: _deploy_lib.sh not found at $DEPLOY_LIB"
    echo "Make sure you have _deploy_lib.sh in: $PARENT_DIR"
    exit 1
fi

# Load shared functions
source "$DEPLOY_LIB"

DEPLOY_LOG="${PROJECT_DIR}/.deploy.log"
export DEPLOY_LOG

# ═══════════════════════════════════════════════════════════════════════════
# PARSE ARGUMENTS
# ═══════════════════════════════════════════════════════════════════════════

FAST_MODE=0
NO_CHECK=0
DRY_RUN=0
ROLLBACK_MODE=0
STATUS_MODE=0
VERSION_ARG=""
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast)
            FAST_MODE=1
            shift
            ;;
        --no-check)
            NO_CHECK=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --rollback)
            ROLLBACK_MODE=1
            shift
            ;;
        --status)
            STATUS_MODE=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$VERSION_ARG" ]]; then
                VERSION_ARG="$1"
            else
                DESCRIPTION="${DESCRIPTION} $1"
            fi
            shift
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF
╔════════════════════════════════════════════════════════════════════════════╗
║                    Deploy Script for ${SERVICE_NAME}                        ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE:
  ./deploy.sh [OPTIONS] [VERSION] [DESCRIPTION]

OPTIONS:
  --fast              Skip health checks (faster, use with caution)
  --no-check          Synonym for --fast
  --dry-run           Show what would happen without actually deploying
  --rollback          Rollback to previous version (:previous tag)
  --status            Show current service status
  --debug             Enable debug output
  -h, --help          Show this help message

EXAMPLES:
  ./deploy.sh
    Auto-bumps patch version, deploys, and verifies health

  ./deploy.sh 1.2.3 "Fixed login bug"
    Deploys specific version with commit message

  ./deploy.sh --fast
    Deploys without health checks (skip if unsure)

  ./deploy.sh --rollback
    Reverts to previous version (docker image tag)

  ./deploy.sh --status
    Shows current deployment status on production

WHERE DEPLOYED:
  Server:  $REMOTE_HOST
  User:    $REMOTE_USER
  Path:    $REMOTE_PATH

TROUBLESHOOTING:
  - Deploy failed? Check: cat $DEPLOY_LOG
  - SSH issues? Verify: ssh -i ~/.ssh/id_rsa ubuntu@$REMOTE_HOST 'echo ok'
  - Health check failed? Manually curl: curl $HEALTH_CHECK_URL
  - Need to rollback? Run: ./deploy.sh --rollback

FOR MORE INFO:
  See: /Users/pierrelindbom/sites/.instructions.md

EOF
}

sanitize_description() {
    echo "$1" | sed 's/^ //; s/ $//'
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN DEPLOYMENT FLOW
# ═══════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  🚀 DEPLOYMENT: ${SERVICE_NAME}                                     ║"
    echo "║  Target: ubuntu@${REMOTE_HOST}:${REMOTE_PATH}                       ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # HANDLE STATUS MODE
    if [[ $STATUS_MODE -eq 1 ]]; then
        show_status "$REMOTE_HOST" "$SERVICE_NAME" "$COMPOSE_FILE_NAME"
        exit 0
    fi

    # HANDLE ROLLBACK MODE
    if [[ $ROLLBACK_MODE -eq 1 ]]; then
        log_info "ROLLBACK MODE - Reverting to previous version"
        if rollback_on_fail "$REMOTE_HOST" "$SERVICE_NAME"; then
            log_success "Rollback complete"
            show_status "$REMOTE_HOST" "$SERVICE_NAME" "$COMPOSE_FILE_NAME"
        else
            log_error "Rollback failed"
            exit 1
        fi
        exit 0
    fi

    # STEP 1: PRE-FLIGHT CHECKS
    log_info "STEP 1/6: Pre-flight checks"
    if ! preflight_check "$REMOTE_HOST" "$PROJECT_DIR" "$COMPOSE_FILE_NAME"; then
        log_error "Pre-flight checks failed"
        exit 1
    fi
    echo ""

    # STEP 2: VERSION MANAGEMENT
    log_info "STEP 2/6: Version management"
    VERSION=$(handle_version "$VERSION_ARG" "$PROJECT_DIR" "$DESCRIPTION")
    DESCRIPTION=$(sanitize_description "$DESCRIPTION")
    log_success "Version: $VERSION | Description: ${DESCRIPTION:-'Deploy'}"
    echo ""

    # STEP 3: DRY-RUN (must be side-effect free)
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY RUN: Would deploy ${SERVICE_NAME}:${VERSION}"
        log_info "Files would be synced to: ubuntu@${REMOTE_HOST}:${REMOTE_PATH}"
        echo ""
        log_success "Dry run complete (no changes made)"
        exit 0
    fi

    # STEP 4: BACKUP FOR ROLLBACK
    log_info "STEP 4/6: Backup current image for rollback"
    backup_image "$REMOTE_HOST" "$SERVICE_NAME"
    echo ""

    # STEP 5: DEPLOY TO REMOTE
    log_info "STEP 5/6: Deploying to remote server"
    if ! deploy_to_remote "$REMOTE_HOST" "$REMOTE_PATH" "$SERVICE_NAME" "$VERSION" "$COMPOSE_FILE_NAME"; then
        log_error "Deployment failed"
        log_error "Rolling back to previous version..."
        if rollback_on_fail "$REMOTE_HOST" "$SERVICE_NAME"; then
            log_warn "Rolled back successfully"
        fi
        exit 1
    fi
    echo ""

    # STEP 6: HEALTH CHECK & LOGGING
    log_info "STEP 6/6: Verifying health"
    
    if [[ $NO_CHECK -eq 0 && $FAST_MODE -eq 0 ]]; then
        # Build health check URL if not provided
        if [[ -z "$HEALTH_CHECK_URL" && -n "$HEALTH_CHECK_PORT" ]]; then
            HEALTH_CHECK_URL="http://localhost:${HEALTH_CHECK_PORT}/health"
        fi
        
        if [[ -n "$HEALTH_CHECK_URL" ]]; then
            if ! health_check "$HEALTH_CHECK_URL" "$REMOTE_HOST"; then
                log_error "Health check failed - rolling back"
                if rollback_on_fail "$REMOTE_HOST" "$SERVICE_NAME"; then
                    log_warn "Rolled back to previous version"
                fi
                exit 1
            fi
        else
            if ! verify_compose_services_running "$REMOTE_HOST" "$REMOTE_PATH" "$COMPOSE_FILE_NAME" "$DOCKER_SERVICES"; then
                log_error "Runtime service validation failed - rolling back"
                if rollback_on_fail "$REMOTE_HOST" "$SERVICE_NAME"; then
                    log_warn "Rolled back to previous version"
                fi
                exit 1
            fi
        fi
    else
        log_warn "Health check skipped (--fast mode)"
    fi
    
    echo ""
    
    # LOG SUCCESS
    log_deployment_success "$SERVICE_NAME" "$VERSION"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  ✅ DEPLOYMENT SUCCESSFUL                                          ║"
    echo "║  Service: ${SERVICE_NAME}                                           ║"
    echo "║  Version: ${VERSION}                                                ║"
    echo "║  Remote: ubuntu@${REMOTE_HOST}:${REMOTE_PATH}                       ║"
    echo "║  Time: $(date)                                                      ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo "Next steps:"
    echo "  1. Verify logs: tail -f $DEPLOY_LOG"
    echo "  2. Check status: ./deploy.sh --status"
    echo "  3. Tail logs: ssh ubuntu@$REMOTE_HOST 'docker compose -f /home/ubuntu/docker/$SERVICE_NAME/$COMPOSE_FILE_NAME logs -f'"
}

# ═══════════════════════════════════════════════════════════════════════════
# EXIT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

trap_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment aborted (exit code: $exit_code)"
    fi
    return $exit_code
}

trap 'trap_exit' EXIT

# ═══════════════════════════════════════════════════════════════════════════
# RUN MAIN
# ═══════════════════════════════════════════════════════════════════════════

main "$@"
