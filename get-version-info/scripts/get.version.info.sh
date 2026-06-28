#!/usr/bin/env bash

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

function get_master_version() {
  local mono_repo=$1

  source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/mono-actions/main/.github/scripts/maven.functions.sh)"

  cd "${mono_repo}" || exit 1
  get_project_version
  return 0
}

function is_latest_stable_release() {
  local release_ver=$1
  local repo_owner=$2

  local latest_branch
  latest_branch=$( \
    gh api \
      "repos/${repo_owner}/hazelcast-mono/branches" \
      --paginate \
      --jq '.[] | select(.name | test("^[0-9]+\\.[0-9]+\\.z$")) | .name' | \
    sort --version-sort --reverse | \
    head --lines 1 \
  )

  if [[ -z ${latest_branch} ]]; then
    echoerr "❌ Failed to resolve 'latest_stable' from repository '${repo_owner}/hazelcast-mono'."
    exit 1
  fi

  if [[ $(get_major_minor_parts "${release_ver}") == $(get_major_minor_parts "${latest_branch}") ]]; then
    echo "true"
  else
    echo "false"
  fi
  
  return 0
}

function is_beta_release() {
  local version=$1
  [[ "${version}" =~ -BETA-[0-9]+$ ]] && echo "true" || echo "false"
}

function is_major_minor() {
  local version=$1
  local parts=($(get_version_parts "${version}"))
  [[ "${parts[2]}" == "0" ]] && echo "true" || echo "false"
  return 0
}

function get_version_parts() {
  local release_ver=$1
  local clean_version=${release_ver%%[-+]*}
  echo ${clean_version//./ }
  return 0
}

function get_major_minor_parts() {
  local release_ver=$1
  local version_parts=($(get_version_parts ${release_ver}))
  echo ${version_parts[0]}.${version_parts[1]}
  return 0
}
