#!/usr/bin/env bash

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

function is_release_next_major() {
  local mono_repo="$1"
  local release_ver="$2"
  local version_parts

  source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/mono-actions/main/.github/scripts/maven.functions.sh)"

  cd ${mono_repo} || exit 1
  local pom_ver
  pom_ver=$(get_project_version)

  version_parts=($(get_version_parts ${release_ver}))
  local rel_major=${version_parts[0]}

  version_parts=($(get_version_parts ${pom_ver}))
  local pom_major=${version_parts[0]}
  local pom_minor_patch=${version_parts[1]}.${version_parts[2]}

  if [[ ${pom_major} -gt ${rel_major} && ${pom_minor_patch} = "0.0" ]]; then
    echo "true"
  else
    echo "false"
  fi

  return 0
}

function is_latest_stable_release() {
  local major_minor
  major_minor=$(get_major_minor_parts "$1")
  local mono_repo="$2"
  
  local latest_stable
  latest_stable=$( \
    gh api \
      "repos/${mono_repo}/branches" \
      --paginate \
      --jq '.[] | select(.name | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' | \
    get_major_minor_parts | \
    sort --version-sort --reverse | \
    head --lines 1 \
  )

  if [[ -z ${latest_stable} ]]; then
    echoerr "Failed to resolve 'latest_stable' from repository '${mono_repo}'."
    exit 1
  fi

  if [[ ${major_minor} = ${latest_stable} ]]; then
    echo "true"
  else
    echo "false"
  fi
  
  return 0
}

function get_version_parts() {
  local version=${1:-$(cat)}
  local clean_version=${version%%[-+]*}

  echo ${clean_version//./ }
}

function get_major_minor_parts() {
  local version_parts=($(get_version_parts ${1:-$(cat)}))
  echo ${version_parts[0]}.${version_parts[1]}
}

function is_beta_release() {
  local version="$1"
  
  if [[ ${version} =~ -BETA-[0-9]+$ ]]; then
    echo "true"
  else
    echo "false"
  fi
}
