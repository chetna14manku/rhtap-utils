#!/bin/bash

# GitLab repository cleanup script
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
    echo "$0 - GitLab repository cleanup script"
    echo ""
    echo "$0 [options]"
    echo ""
    echo "Environment Variables Required:"
    echo "  GITLAB_TOKEN        - GitLab personal access token"
    echo "  GITLAB_GROUP        - GitLab group ID"
    echo "  GITLAB_URL          - GitLab instance URL (default: https://gitlab.com)"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run       Enable dry run mode - no actual deletions"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Dry run for GitLab cleanup"
    echo "  GITLAB_TOKEN=xxx GITLAB_GROUP=123 --dry-run $0"
    echo ""
    echo "  # Actually delete repositories (disable dry run)"
    echo "  GITLAB_TOKEN=xxx GITLAB_GROUP=123 dry_run=false $0"
    echo ""
}

gitlab_cleanup() {
    log "=== GitLab Cleanup ==="
    
    export GITLAB_TOKEN="${GITLAB_TOKEN:-$(cat /usr/local/rhtap-cli-install/gitlab_token 2>/dev/null || echo "")}"
    export GITLAB_GROUP="${GITLAB_GROUP:-$(cat /usr/local/rhtap-cli-install/gitlab-group-id 2>/dev/null || echo "")}"
    export GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
    AUTH_HEADER="PRIVATE-TOKEN: $GITLAB_TOKEN"

   
    # Calculate cutoff time
    cutoff_date=$(date -d "-${DAYS} days" --iso-8601)
    
    log "Checking GitLab group: $GITLAB_GROUP"
    log "GitLab URL: $GITLAB_URL"
    log "Cutoff date: $cutoff_date"
    echo ""
    
    # Fetch projects from group
    projects=$(curl -s -H "$AUTH_HEADER" \
        "$GITLAB_URL/api/v4/groups/$GITLAB_GROUP/projects?per_page=200&sort=name")
    
    if [ "$(echo $projects | jq -r .status 2>/dev/null)" ]; then
        log "Error fetching projects: $projects"
        return 1
    fi
    
    # Process projects
    echo "$projects" | jq -c '.[]' | while read -r project; do
        project_name=$(echo $project | jq -r '.name')
        project_id=$(echo $project | jq -r '.id')
        last_activity=$(echo $project | jq -r '.last_activity_at')
        
        # Convert last activity to Unix timestamp for comparison
        last_activity_time=$(date -d "$last_activity" +%s)
        cutoff_time=$(date -d "$cutoff_date" +%s)
        
        # Check if project matches pattern and is old enough
        if [[ $project_name =~ $repo_name_regex ]] && [ $last_activity_time -lt $cutoff_time ]; then
            if [[ "$dry_run" == "true" ]]; then
                log "[DRY RUN] Would delete project '$project_name' (ID: $project_id). Last activity: $last_activity"
            else
                log "Deleting project '$project_name' (ID: $project_id). Last activity: $last_activity"
                delete_response=$(curl -s -X DELETE \
                    -H "$AUTH_HEADER" \
                    "$GITLAB_URL/api/v4/projects/$project_id")
                
                if [ -z "$delete_response" ]; then
                    log "Project '$project_name' deleted successfully."
                else
                    log "Failed to delete project '$project_name': $delete_response"
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

log "GitLab Repository Cleanup Script"
log "================================"
log "Dry run: $dry_run"
log "Days threshold: $DAYS"
echo ""

# Execute GitLab cleanup
gitlab_cleanup

log "GitLab cleanup completed!"