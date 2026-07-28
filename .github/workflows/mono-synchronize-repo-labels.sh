#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

REPO_NAME=$1

if [ -z "$REPO_NAME" ]; then
    echo "Error: Repository name not specified."
    echo "Usage: cat labels.json | $0 <repo_owner/repo_name>"
    exit 1
fi

echo "Setting labels for $REPO_NAME..."

while read -r label; do
    label_name=$(echo "$label" | jq -r '.name')
    label_description=$(echo "$label" | jq -r '.description')
    label_color=$(echo "$label" | jq -r '.color')

    gh label create --repo="$REPO_NAME" "$label_name" \
        --description "$label_description" \
        --color "$label_color" \
        --force
    echo "Label '$label_name' set for $REPO_NAME."
done < <(jq -c '.[]')

echo "Labels set for $REPO_NAME."
