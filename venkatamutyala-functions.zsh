function gha-ls() {
    # Define colors for alternating rows, statuses, and conclusions
    RESET="\033[0m"
    YELLOW="\033[1;33m"
    GREEN="\033[1;32m"
    RED="\033[1;31m"
    BLUE="\033[1;34m"
    CYAN="\033[1;36m"
    MAGENTA="\033[1;35m"
    GRAY="\033[1;30m"    # Alternate row color

    # Function to convert ISO 8601 timestamp to "time ago" format
    time_ago() {
        local created_at="$1"
        local now=$(date -u +%s)
        local created_at_seconds=$(date -u -d "$created_at" +%s)
        local diff=$((now - created_at_seconds))

        if (( diff < 60 )); then
            echo "$diff seconds ago"
        elif (( diff < 3600 )); then
            echo "$((diff / 60)) minutes ago"
        elif (( diff < 86400 )); then
            echo "$((diff / 3600)) hours ago"
        else
            echo "$((diff / 86400)) days ago"
        fi
    }

    # Prompt for statuses, conclusions, and number of jobs to retrieve
    echo "Please enter the GitHub organization name:"
    read -r ORG_NAME
    echo "Please enter the statuses to filter (e.g., in_progress, completed, queued, waiting). Leave empty for all:"
    read -r statuses
    echo "Please enter the conclusions to filter (e.g., success, failure, cancelled). Leave empty for all:"
    read -r conclusions
    echo "Please enter the number of jobs to pull up (e.g., 5, 10, 20):"
    read -r job_limit

    # If no input is given, set defaults
    ORG_NAME=${ORG_NAME:-"GlueOps"}
    statuses=${statuses:-"all"}
    conclusions=${conclusions:-"all"}
    job_limit=${job_limit:-1}

    # Print table header with column names
    echo -e "$(printf '%-120s %-25s %-12s %-12s\n' 'Job URL' 'Created At' 'Status' 'Conclusion')"
    echo -e "$(printf '%-120s %-25s %-12s %-12s\n' '-------' '----------' '------' '----------')"

    # Get a list of all repositories in the organization
    repos=$(gh repo list "$ORG_NAME" --limit 1000 --json name --jq '.[].name')

    # Loop through each repository
    for repo in $repos; do
        # List active workflow runs based on user input statuses and conclusions
        if [[ "$statuses" == "all" ]]; then
            status_filter=""
        else
            status_filter="--status $statuses"
        fi

        # List the last N runs based on user input
        last_runs=$(gh run list --repo "$ORG_NAME/$repo" $status_filter --limit "$job_limit" --json databaseId,name,status,conclusion,createdAt)

        # Combine all last runs and apply conclusion filter if necessary
        if [[ "$conclusions" != "all" ]]; then
            combined_runs=$(echo "$last_runs" | jq --arg conclusions "$conclusions" '[.[] | select(.conclusion == $conclusions)]')
        else
            combined_runs="$last_runs"
        fi

        # Sort the runs by 'createdAt' in descending order
        sorted_runs=$(echo "$combined_runs" | jq 'sort_by(.createdAt) | reverse')

        # Check if there are any runs to display
        run_count=$(echo "$sorted_runs" | jq length)

        if [[ "$run_count" -gt 0 ]]; then
            # Iterate over each run to get details and URL
            row=1
            echo "$sorted_runs" | jq -r '.[] | .databaseId as $id | "Workflow Run: \(.name) (ID: \($id)) - Status: \(.status) - Conclusion: \(.conclusion) - Created At: \(.createdAt)\nGetting URL..."' | while read -r workflow_info; do
                run_id=$(echo "$workflow_info" | grep -oP '(?<=\(ID: ).*(?=\))')
                if [ -n "$run_id" ]; then
                    # Fetch the workflow URL using gh run view
                    run_url=$(gh run view "$run_id" --repo "$ORG_NAME/$repo" --json url --jq '.url')
                    status=$(echo "$workflow_info" | grep -oP '(?<=- Status: ).*(?= - Conclusion)')
                    conclusion=$(echo "$workflow_info" | grep -oP '(?<=- Conclusion: ).*(?= - Created)')
                    created_at=$(echo "$workflow_info" | grep -oP '(?<=- Created At: ).*')

                    # Convert created_at to "time ago" format
                    created_at_ago=$(time_ago "$created_at")

                    # Pad the status and conclusion to ensure proper alignment
                    status_padded=$(printf "%-12s" "$status")
                    conclusion_padded=$(printf "%-12s" "$conclusion")

                    # Color-code the status
                    if [[ "$status" == "in_progress" ]]; then
                        status_color="$YELLOW$status_padded$RESET"
                    elif [[ "$status" == "completed" ]]; then
                        status_color="$GREEN$status_padded$RESET"
                    elif [[ "$status" == "queued" ]]; then
                        status_color="$BLUE$status_padded$RESET"
                    elif [[ "$status" == "waiting" ]]; then
                        status_color="$CYAN$status_padded$RESET"
                    else
                        status_color="$status_padded"
                    fi

                    # Color-code the conclusion
                    if [[ "$conclusion" == "success" ]]; then
                        conclusion_color="$GREEN$conclusion_padded$RESET"
                    elif [[ "$conclusion" == "failure" ]]; then
                        conclusion_color="$RED$conclusion_padded$RESET"
                    elif [[ "$conclusion" == "cancelled" ]]; then
                        conclusion_color="$YELLOW$conclusion_padded$RESET"
                    elif [[ "$conclusion" == "timed_out" ]]; then
                        conclusion_color="$MAGENTA$conclusion_padded$RESET"
                    else
                        conclusion_color="$conclusion_padded"
                    fi

                    # Alternate row colors
                    if (( row % 2 == 0 )); then
                        row_color="$GRAY"
                    else
                        row_color=""
                    fi

                    # Print the job URL, created_at (time ago), status, and conclusion in columns with alternating row colors
                    echo -e "${row_color}$(printf '%-120s %-25s %-12s %-12s\n' "$run_url" "$created_at_ago" "$status_color" "$conclusion_color")${RESET}"

                    # Add an empty line between rows for spacing
                    echo ""

                    ((row++))
                fi
            done
        else
            echo "No workflow runs found for $ORG_NAME/$repo"
        fi
    done
}



debug-busybox() {
    kubectl run -i --tty --rm busybox --image=busybox --restart=Never -- sh
}

debug-ubuntu() {
    kubectl run -i --tty --rm busybox --image=ubuntu --restart=Never -- sh
}


