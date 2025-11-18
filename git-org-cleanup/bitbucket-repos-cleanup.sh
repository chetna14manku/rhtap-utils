#!/bin/bash

# Bitbucket repository cleanup script
# Set dry_run to true for not deleting repos, it will provide list of repos to delete
dry_run="${dry_run:-true}"

# Log function for consistent output formatting
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Common configuration
DAYS="${DAYS:-14}"
repo_name_regex="^[a-z0-9-]*(python|dotnet-basic|java-quarkus|go|nodejs|java-springboot)[a-z0-9-]*(-gitops)?$"

help_text() {
    echo ""
    echo "$0 - Bitbucket repository cleanup script"
    echo ""
    echo "$0 [options]"
    echo ""
    echo "Environment Variables Required:"
    echo "  BITBUCKET_USERNAME  - Bitbucket username"
    echo "  BITBUCKET_PASSWORD  - Bitbucket app password"
    echo "  BITBUCKET_WORKSPACE - Bitbucket workspace name"
    echo "  BITBUCKET_PROJECT   - Bitbucket project key (optional - if not set, searches all workspace repos)"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run       Enable dry run mode - no actual deletions"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Dry run for Bitbucket cleanup"
    echo "  BITBUCKET_USERNAME=user BITBUCKET_PASSWORD=pass BITBUCKET_WORKSPACE=workspace --dry-run $0"
    echo ""
    echo "  # Actually delete repositories (disable dry run)"
    echo "  BITBUCKET_USERNAME=user BITBUCKET_PASSWORD=pass BITBUCKET_WORKSPACE=workspace dry_run=false $0"
    echo ""
}

bitbucket_cleanup() {
    log "=== Bitbucket Cleanup ==="
    
    export BITBUCKET_USERNAME="${BITBUCKET_USERNAME:-$(cat /usr/local/rhtap-cli-install/bitbucket-username 2>/dev/null || echo "")}"
    export BITBUCKET_PASSWORD="${BITBUCKET_PASSWORD:-$(cat /usr/local/rhtap-cli-install/bitbucket-password 2>/dev/null || echo "")}"
    export BITBUCKET_WORKSPACE="${BITBUCKET_WORKSPACE:-rhtap-test}"
    export BITBUCKET_PROJECT="${BITBUCKET_PROJECT:-RHTAP}"
    AUTH_CREDS="$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD"
    
    # Calculate cutoff time
    cutoff_date=$(date -d "-${DAYS} days" --iso-8601)
    cutoff_time=$(date -d "$cutoff_date" +%s)
    
    log "Checking Bitbucket workspace: $BITBUCKET_WORKSPACE"
    log "Checking Bitbucket project: $BITBUCKET_PROJECT"
    log "Cutoff date: $cutoff_date"
    echo ""
    
    # Fetch repositories for specific project
    repos=$(curl -s -u "$AUTH_CREDS" \
        "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_WORKSPACE?q=project.key=\"$BITBUCKET_PROJECT\"&pagelen=200")
    
    if [ "$(echo $repos | jq -r .error 2>/dev/null)" ]; then
        log "Error fetching repositories: $repos"
        return 1
    fi
    
    # Process repositories
    echo "$repos" | jq -c '.values[]' | while read -r repo; do
        repo_name=$(echo $repo | jq -r '.name')
        updated_on=$(echo $repo | jq -r '.updated_on')
        
        # Convert updated_on to Unix timestamp for comparison
        updated_time=$(date -d "$updated_on" +%s)
        
        # Check if repository matches pattern and is old enough
        if [[ $repo_name =~ $repo_name_regex ]] && [ $updated_time -lt $cutoff_time ]; then
            if [[ "$dry_run" == "true" ]]; then
                log "[DRY RUN] Would delete repository '$repo_name'. Last updated: $updated_on"
            else
                log "Deleting repository '$repo_name'. Last updated: $updated_on"
                delete_response=$(curl -s -X DELETE \
                    -u "$AUTH_CREDS" \
                    "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_WORKSPACE/$repo_name")
                
                if [ -z "$delete_response" ]; then
                    log "Repository '$repo_name' deleted successfully."
                else
                    log "Failed to delete repository '$repo_name': $delete_response"
                fi
            fi
        fi
    done
}

# Parse command line arguments
while test $# -gt 0; do
    case "$1" in
        -h|--help)
            help_text
            exit 0
            ;;
        -d|--dry-run)
            dry_run="true"
            shift
            ;;
        *)
            echo "Error: Invalid command syntax"
            help_text
            exit 1
            ;;
    esac
done

log "Bitbucket Repository Cleanup Script"
log "==================================="
log "Dry run: $dry_run"
log "Days threshold: $DAYS"
echo ""

# Execute Bitbucket cleanup
bitbucket_cleanup

log "Bitbucket cleanup completed!"