#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

# Function to get labels from a GitHub repository
get_labels() {
    local repository="$1"
    gh -R "$repository" label list --sort name --limit 99999 --json 'name,color,description'
}

# Parse command-line arguments
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <repository1> [<repository2> ...]"
    exit 1
fi

# List of repositories from command-line arguments
repositories=("$@")

# Loop through repositories and get labels
mergedArray=()
for repo in "${repositories[@]}"; do
    labels=$(get_labels "$repo")
    array=($(echo "$labels" | jq -c '.[]'))
    mergedArray+=("${array[@]}")
done

# Merge and remove duplicates based on the "name" key
mergedArray=($(echo "${mergedArray[@]}" | jq -s 'group_by(.name) | map(.[0]) | sort_by(.name)'))

# Convert the merged array back to a JSON string
mergedJson=$(echo "${mergedArray[@]}" | jq -s '.[0]')

# Display the merged JSON string
echo "$mergedJson"
