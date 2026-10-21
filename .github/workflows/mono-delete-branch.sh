#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <repository> <branch-to-delete>"
    exit 1
fi

REPO_NAME=$1
BRANCH_NAME=$2

if [[ $BRANCH_NAME =~ ^[0-9]+\.[0-9]+\.[0-9z]+(-BETA-[0-9]+)?$|^data-migration-5.3$ ]]; then
 if gh api "repos/$REPO_NAME/branches/$BRANCH_NAME" >/dev/null 2>&1; then
    echo "Deleting $BRANCH_NAME from ${REPO_NAME} repository"
    gh api \
    --method DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
      "/repos/${REPO_NAME}/git/refs/heads/${BRANCH_NAME}"
 else
   echo "Branch $BRANCH_NAME does not exist in ${REPO_NAME} repository"
 fi
else
  echo "Branch $BRANCH_NAME does not match pattern. Skipping"
fi