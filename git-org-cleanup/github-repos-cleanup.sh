#!/bin/bash

# GitHub repository cleanup script
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
    echo "$0 - GitHub repository cleanup script"
    echo ""
    echo "$0 [options]"
    echo ""
    echo "Environment Variables Required:"
    echo "  GITHUB_ORG_TOKEN    - GitHub personal access token"
    echo "  GITHUB_ORG_NAME     - GitHub organization name"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run       Enable dry run mode - no actual deletions"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Dry run for GitHub cleanup"
    echo "  GITHUB_ORG_TOKEN=xxx GITHUB_ORG_NAME=myorg --dry-run $0"
    echo ""
    echo "  # Actually delete repositories (disable dry run)"
    echo "  GITHUB_ORG_TOKEN=xxx GITHUB_ORG_NAME=myorg dry_run=false $0"
    echo ""
}

github_cleanup() {
    log "=== GitHub Cleanup ==="
   
    export GITHUB_TOKEN="${GITHUB_ORG_TOKEN:-$(cat /usr/local/rhtap-cli-install/github_token 2>/dev/null || echo "")}"
    export GITHUB_ORG="${GITHUB_ORG_NAME:-rhtap-rhdh-qe}"
    AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
    
    # Calculate cutoff time
    now=$(date +%s)
    cutoff_time=$((now - DAYS * 24 * 60 * 60))
    
    log "Checking GitHub organization: $GITHUB_ORG"
    log "Cutoff date: $(date -d "@$cutoff_time")"
    
    # Fetch repositories
    repos=$(curl -s -X GET -H "$AUTH_HEADER" "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=200&sort=name")
    if [ "$(echo $repos | jq -r .status 2>/dev/null)" ]; then
        log "Error fetching repositories: $repos"
        return 1
    fi
    
    # Process repositories
    echo "$repos" | jq -c '.[]' | while read -r repo; do
        repo_name=$(echo $repo | jq -r '.name')
        last_push=$(echo $repo | jq -r '.pushed_at')
        echo "Repository: $repo_name, Last pushed: $last_push"
        
        # Convert the last push time to Unix timestamp
        last_push_time=$(date -d "$last_push" +%s)
        
        # Check if repository matches pattern and is old enough
        if [[ $repo_name =~ $repo_name_regex ]] && [ $last_push_time -lt $cutoff_time ]; then
            if [[ "$dry_run" == "true" ]]; then
                log "[DRY RUN] Would delete repository '$repo_name'. Last updated: $last_push"
            else
                log "Deleting repository '$repo_name'. Last updated: $last_push"
                delete_response=$(curl -s -X DELETE \
                    -H "$AUTH_HEADER" \
                    "https://api.github.com/repos/$GITHUB_ORG/$repo_name")
                
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

log "GitHub Repository Cleanup Script"
log "================================"
log "Dry run: $dry_run"
log "Days threshold: $DAYS"
echo ""

# Execute GitHub cleanup
github_cleanup

log "GitHub cleanup completed!"