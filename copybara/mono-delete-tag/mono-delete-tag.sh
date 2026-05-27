#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <repository> <tag-to-delete>"
  exit 1
fi

REPO_NAME=$1
TAG_NAME=$2

# Remove only well known tags, the regex below covers the following patterns:
#  - "v[0-9]+.[0-9]+.[0-9]"
#  - "v[0-9]+.[0-9]+.[0-9]+-BETA-[0-9]+"
if [[ ${TAG_NAME} =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-BETA-[0-9]+)?$ ]]; then
  if gh api "repos/${REPO_NAME}/git/refs/tags/${TAG_NAME}" >/dev/null 2>&1; then
    echo "Deleting tag '${TAG_NAME}' from '${REPO_NAME}' repository"
    gh api \
      --method DELETE \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/${REPO_NAME}/git/refs/tags/${TAG_NAME}"
  else
    echo "Tag '${TAG_NAME}' does not exist in '${REPO_NAME}' repository"
  fi
else
  echo "Tag '${TAG_NAME}' does not match pattern. Skipping"
fi
