#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

REPO_NAME=$1
BRANCH_NAME=$2

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

find_matching_commit_in_subrepo() {
  local starting_commit=${1}
  local subrepo_path=${2}

  local commit=${starting_commit}
  while [[ -n "${commit}" ]]; do
      local found_commit
      found_commit=$(git -C "${subrepo_path}" log --all --grep="GitOrigin-RevId: ${commit}" --format="%H" -n 1)
      if [[ -n "${found_commit}" ]]; then
         echo "${found_commit}"
         exit
      fi
      commit=$(git log --pretty=format:"%H" -n 1 "${commit}^")
  done

  exit 1
}

find_closest_merge_base_on_release_branches() {

  if ! git rev-parse --quiet --verify "${BRANCH_NAME}" >/dev/null; then
    echo "Error: Invalid commit hash: ${BRANCH_NAME}" >&2
    exit 2
  fi

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref "${BRANCH_NAME}")
  local branches
  branches=$(gh api "repos/${REPO_NAME}/branches" --paginate --jq '.[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9z]+(-BETA-[0-9]+)?$|^master$|^data-migration-5.3$')

  local closest_merge_base_distance=""
  local closest_merge_base=""

  for branch in ${branches}; do
    if [[ "${branch}" == "${current_branch}" ]]; then
      continue
    fi

    local merge_base_on_branch
    merge_base_on_branch=$(git merge-base "${BRANCH_NAME}" "origin/${branch}")
    local merge_base_distance
    if [[ -n "${merge_base_on_branch}" ]]; then
      merge_base_distance=$(git rev-list --ancestry-path --count "${merge_base_on_branch}..${BRANCH_NAME}")
    fi

    if [[ -z "${closest_merge_base_distance}" ]] || [[ "${merge_base_distance}" -lt "${closest_merge_base_distance}" ]]; then
      closest_merge_base_distance="${merge_base_distance}"
      closest_merge_base="${merge_base_on_branch}"
    fi
  done

  if [[ -z "${closest_merge_base}" ]]; then
    echo "Error: No merge base found." >&2
    exit 3
  fi

  echo "${closest_merge_base}"
}

if ! gh api "repos/${REPO_NAME}/branches/${BRANCH_NAME}" >/dev/null 2>&1; then
  echo "Branch ${BRANCH_NAME} does not exist in ${REPO_NAME} repo"
  MONOREPO_MERGE_BASE=$(find_closest_merge_base_on_release_branches)
  if [[ -n "${MONOREPO_MERGE_BASE}" ]]; then
    TMP_REPO_DIR=tmp-repo
    gh repo clone "${REPO_NAME}" "${TMP_REPO_DIR}" -- --filter=blob:none --no-checkout
    SUBREPO_MERGE_BASE=$(find_matching_commit_in_subrepo "${MONOREPO_MERGE_BASE}" "${TMP_REPO_DIR}" )
    if [[ -n "${SUBREPO_MERGE_BASE}" ]]; then
      # create new branch
      gh api -X POST "repos/${REPO_NAME}/git/refs" \
        -F ref="refs/heads/${BRANCH_NAME}" \
        -F sha="${SUBREPO_MERGE_BASE}"
    else
      echoerr "Can't find merge base commit for creation '${BRANCH_NAME}' branch in ${REPO_NAME} repo. Monorepo merge base: ${MONOREPO_MERGE_BASE}"
      exit 1
    fi 
    rm -rf "${TMP_REPO_DIR}"
  fi
fi