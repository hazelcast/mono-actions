#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

SOURCE_REPO_NAME=$1
TARGET_REPO_NAME=$2

export IFS=$'\r'"$IFS"

if [ -z "$SOURCE_REPO_NAME" ]; then
    echo "Error: Source repository name not specified."
    echo "Usage: $0 <source repo_owner/repo_name> <target repo_owner/repo_name>"
    exit 1
fi

if [ -z "$TARGET_REPO_NAME" ]; then
    echo "Error: Target repository name not specified."
    echo "Usage: $0 <source repo_owner/repo_name> <target repo_owner/repo_name>"
    exit 2
fi

echo "Copying milestones from $SOURCE_REPO_NAME to $TARGET_REPO_NAME..."

get_milestones() {
    local repository="$1"
    gh api "repos/$repository/milestones?state=all" --paginate --jq '.[] | {title, number, description, state, due_on}' | jq -s
}

source_milestones=$(get_milestones "$SOURCE_REPO_NAME")
target_milestones=$(get_milestones "$TARGET_REPO_NAME")

get_target_milestone_number() {
    title_to_check="$1"
    echo "$target_milestones" | jq -r --arg title_to_check "$title_to_check" '.[] | select(.title == $title_to_check) | .number'
}

while read -r milestone; do
    title=$(echo "$milestone" | jq -r '.title')
    description=$(echo "$milestone" | jq -r '.description // ""')
    state=$(echo "$milestone" | jq -r '.state')
    due_on=$(echo "$milestone" | jq -r '.due_on // ""')
    # Check if milestone already exists in the destination repository
    milestone_number=$(get_target_milestone_number "$title")
    api_endpoint="/repos/$TARGET_REPO_NAME/milestones"
    if [ -n "$milestone_number" ]; then
        api_endpoint="$api_endpoint/$milestone_number"
    fi
    eval gh api --silent "$api_endpoint" \
        -f title="'$title'" \
        -f state="$state" \
        -f description="'$description'" \
        $( [ -n "$due_on" ] && echo "--field due_on=\"$due_on\"" )

    [ -n "$milestone_number" ] && action="updated" || action="created"
    echo "Milestone '$title' $action."
done < <(echo "$source_milestones" | jq -c '.[]')

echo "Milestones set for $TARGET_REPO_NAME."



