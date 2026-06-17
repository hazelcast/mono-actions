#!/usr/bin/env bash

set -euo pipefail ${RUNNER_DEBUG:+-x}
export GH_DEBUG=${RUNNER_DEBUG:+1}

REPO_NAME=$1
BRANCH_NAME=$2

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

TMP_REPO_DIR=tmp-repo
gh repo clone "${REPO_NAME}" "${TMP_REPO_DIR}" -- --filter=blob:none --no-checkout --single-branch --branch "${BRANCH_NAME}"
LAST_MONOREPO_COMMIT=$(git --git-dir="${TMP_REPO_DIR}/.git" log --grep="GitOrigin-RevId"  --format="%B" -n 1 | awk '/GitOrigin-RevId:/ {print $2}')
rm -rf "${TMP_REPO_DIR}"
INITIAL_MONOREPO_COMMIT=$(git log --grep="Add hazelcast/ from hazelcast/.*" --format="%H" -n 1)

get_ancestor_distance() {
    local commit_hash="$1"
    local path_length
    path_length=$(git rev-list --ancestry-path --count "${commit_hash}..HEAD")
    echo "${path_length}"
}

find_closer_ancestor() {
    commit1="${1-}"
    commit2="${2-}"

    if [[ -z "${commit1}" ]] && [[ -z "${commit2}" ]]; then
        echoerr "Both commits are empty. Failing."
        exit 1
    elif [[ -z "${commit1}" ]]; then
        result_commit=${commit2}
    elif [[ -z "${commit2}" ]]; then
        result_commit=${commit1}
    else
        local length_commit1
        length_commit1=$(get_ancestor_distance "${commit1}")
        local length_commit2
        length_commit2=$(get_ancestor_distance "${commit2}")

        if [[ ${length_commit1} -lt ${length_commit2} ]]; then
            result_commit=${commit1}
        else
            result_commit=${commit2}
        fi
    fi
    echo "${result_commit}"
}

find_closer_ancestor "${LAST_MONOREPO_COMMIT}" "${INITIAL_MONOREPO_COMMIT}"