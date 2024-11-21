
function dev-start() {
    if tmux has-session -t metrics 2>/dev/null; then
        tmux attach-session -t metrics
    else
        tmux new-session -d -s metrics \; \
            split-window -h \; \
            send-keys 'htop' C-m \; \
            split-window -v \; \
            send-keys 'sudo nethogs' C-m \; \
            select-pane -R \; \
            attach
    fi
}


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

    # Default values
    ORG_NAME="GlueOps"
    statuses="all"
    conclusions="all"
    job_limit=1

    # Parse command-line options
    while [[ "$1" != "" ]]; do
        case $1 in
            -o | --org )
                shift
                ORG_NAME="$1"
                ;;
            -s | --statuses )
                shift
                statuses="$1"
                ;;
            -c | --conclusions )
                shift
                conclusions="$1"
                ;;
            -l | --limit )
                shift
                job_limit="$1"
                ;;
            -h | --help )
                echo "Usage: gha-ls [options]"
                echo "Options:"
                echo "  -o, --org            GitHub organization name (default: GlueOps)"
                echo "  -s, --statuses       Statuses to filter (e.g., in_progress, completed, queued, waiting). Use 'all' for all statuses."
                echo "  -c, --conclusions    Conclusions to filter (e.g., success, failure, cancelled). Use 'all' for all conclusions."
                echo "  -l, --limit          Number of jobs to retrieve per repository (default: 1)"
                echo "  -h, --help           Display this help message"
                return
                ;;
            * )
                echo "Invalid option: $1"
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
        shift
    done

    # Print table header with column names
    echo -e "$(printf '%-120s %-25s %-12s %-12s\n' 'Job URL' 'Created At' 'Status' 'Conclusion')"
    echo -e "$(printf '%-120s %-25s %-12s %-12s\n' '-------' '----------' '------' '----------')"

    # Get a list of all repositories in the organization
    repos=$(gh repo list "$ORG_NAME" --limit 1000 --json name --jq '.[].name')

    # Loop through each repository
    echo "$repos" | while IFS= read -r repo; do
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
            echo "$sorted_runs" | jq -r '.[] | .databaseId as $id | "Workflow Run: \(.name) (ID: \($id)) - Status: \(.status) - Conclusion: \(.conclusion) - Created At: \(.createdAt)\nGetting URL..."' | while IFS= read -r workflow_info; do
                run_id=$(echo "$workflow_info" | grep -oP '(?<=\(ID: ).*(?=\))')
                if [ -n "$run_id" ]; then
                    # Fetch the workflow URL using gh run view
                    run_url=$(gh run view "$run_id" --repo "$ORG_NAME/$repo" --json url --jq '.url')
                    run_status=$(echo "$workflow_info" | grep -oP '(?<=- Status: ).*(?= - Conclusion)')
                    conclusion=$(echo "$workflow_info" | grep -oP '(?<=- Conclusion: ).*(?= - Created)')
                    created_at=$(echo "$workflow_info" | grep -oP '(?<=- Created At: ).*')

                    # Convert created_at to "time ago" format
                    created_at_ago=$(time_ago "$created_at")

                    # Pad the status and conclusion to ensure proper alignment
                    status_padded=$(printf "%-12s" "$run_status")
                    conclusion_padded=$(printf "%-12s" "$conclusion")

                    # Color-code the status
                    if [[ "$run_status" == "in_progress" ]]; then
                        status_color="$YELLOW$status_padded$RESET"
                    elif [[ "$run_status" == "completed" ]]; then
                        status_color="$GREEN$status_padded$RESET"
                    elif [[ "$run_status" == "queued" ]]; then
                        status_color="$BLUE$status_padded$RESET"
                    elif [[ "$run_status" == "waiting" ]]; then
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



debug-pod() {
    # Default values
    IMAGE="busybox"
    COMMAND="sh"

    # Parse command-line options
    while [[ "$1" != "" ]]; do
        case $1 in
            -i | --image )
                shift
                IMAGE="$1"
                ;;
            -c | --command )
                shift
                COMMAND="$1"
                ;;
            -h | --help )
                echo "Usage: debug-pod [options]"
                echo "Options:"
                echo "  -i, --image          Docker image to use (default: busybox)"
                echo "  -c, --command        Command to run inside the container (default: sh)"
                echo "  -h, --help           Display this help message"
                return
                ;;
            * )
                echo "Invalid option: $1"
                echo "Use -h or --help for usage information."
                return 1
                ;;
        esac
        shift
    done

    kubectl run -i --tty --rm debug-pod --image="$IMAGE" --restart=Never -- "$COMMAND"
}








gha-trigger() {
  # Default values
  AUTO_APPROVE=false
  BRANCH="main"

  # Parse command-line options
  while getopts ":yo:w:b:h" opt; do
    case $opt in
      y)
        AUTO_APPROVE=true
        ;;
      o)
        ORG_NAME="$OPTARG"
        ;;
      w)
        WORKFLOW_FILE="$OPTARG"
        ;;
      b)
        BRANCH="$OPTARG"
        ;;
      h)
        echo "Usage: $0 [-y] -o <organization_name> -w <workflow_file> [-b <branch_name>]"
        return
        ;;
      \?)
        echo "Invalid option: -$OPTARG" >&2
        echo "Usage: $0 [-y] -o <organization_name> -w <workflow_file> [-b <branch_name>]"
        return 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument." >&2
        echo "Usage: $0 [-y] -o <organization_name> -w <workflow_file> [-b <branch_name>]"
        return 1
        ;;
    esac
  done
  shift $((OPTIND -1))

  # Check for required arguments
  if [[ -z "$ORG_NAME" || -z "$WORKFLOW_FILE" ]]; then
    echo "Error: Organization name and workflow file are required."
    echo "Usage: $0 [-y] -o <organization_name> -w <workflow_file> [-b <branch_name>]"
    return 1
  fi

  # Fetch the list of repositories
  echo "Fetching repositories for organization '$ORG_NAME'..."

  # Read the repositories into an array
  repos=("${(@f)$(gh repo list "$ORG_NAME" --limit 1000 --json name -q '.[].name')}")

  if [ ${#repos[@]} -eq 0 ]; then
    echo "No repositories found for organization '$ORG_NAME'."
    exit 1
  fi

  # Loop through each repository
  for repo in "${repos[@]}"; do
    echo "Processing repository: $repo"

    # Fetch workflows in the repository
    workflows_json=$(gh api repos/"$ORG_NAME"/"$repo"/actions/workflows 2>/dev/null)

    # Check if the API call was successful
    if [ $? -ne 0 ] || [ -z "$workflows_json" ]; then
      echo "Failed to fetch workflows for $repo or no workflows found."
      echo "---------------------------------------"
      continue
    fi

    # Try to find the workflow by path (filename)
    workflow_id=$(echo "$workflows_json" | jq -r ".workflows[] | select(.path==\".github/workflows/$WORKFLOW_FILE\") | .id")

    if [ -n "$workflow_id" ] && [ "$workflow_id" != "null" ]; then
      echo "Found workflow '$WORKFLOW_FILE' in $repo."

      # Check for auto-approve or prompt user
      if [ "$AUTO_APPROVE" = true ]; then
        echo "Auto-approve enabled. Triggering workflow in $repo..."
        trigger=true
      else
        vared -p "Do you want to trigger the workflow in $repo? (y/n): " -c choice
        case "$choice" in
          y|Y ) trigger=true ;;
          * ) trigger=false ;;
        esac
      fi

      if [ "$trigger" = true ]; then
        # Trigger the workflow
        gh workflow run "$workflow_id" --repo "$ORG_NAME"/"$repo" --ref "$BRANCH"
        echo "Workflow triggered in $repo."
      else
        echo "Skipped triggering workflow in $repo."
      fi
    else
      echo "Workflow '$WORKFLOW_FILE' not found in $repo."
    fi

    echo "---------------------------------------"
  done

  echo "Workflow triggering process completed."
}
