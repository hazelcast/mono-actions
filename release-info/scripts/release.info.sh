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
  return 0
}

function is_major_minor() {
  local version=$1
  local parts=($(get_version_parts "${version}"))
  [[ "${parts[2]}" == "0" ]] && echo "true" || echo "false"
  return 0
}

function is_patch_release() {
  local version=$1
  local parts=($(get_version_parts "${version}"))
  [[ -n "${parts[2]}" && "${parts[2]}" -gt 0 ]] && echo "true" || echo "false"
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

function get_latest_mc_version() {
  local latest_mc_ver
  latest_mc_ver=$( \
    gh api \
      repos/hazelcast/management-center/tags \
      --paginate \
      --jq '.[] | select(.name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name | ltrimstr("v")' | \
    sort --version-sort --reverse | \
    head --lines 1 \
  )

  if [[ -z "${latest_mc_ver}" ]]; then
    echoerr "❌ Failed to get latest MC ZIP from GitHub"
    exit 1
  fi

  echo "${latest_mc_ver}"
  return 0
}

function log_version_variables() {
  local json_file=$1

  local pretty_json
  pretty_json=$(jq '.' "${json_file}")

  echodebug "========================================="
  echodebug "   GET-VERSION-INFO OUTPUT VARIABLES"
  echodebug "========================================="
  echodebug "${pretty_json}"
  echodebug "========================================="
  return 0
}

function generate_rel_info_json() {
  local output_file=$1
  local release_version=$2
  local repo_owner=$3
  local mono_path=$4

  local master_ver
  local master_mm
  master_ver=$(get_master_version "${mono_path}")
  master_mm=$(get_major_minor_parts "${master_ver}")

  local rel_mm
  local is_latest_stable
  local is_beta
  local is_rel_mm
  local is_patch
  
  rel_mm=$(get_major_minor_parts "${release_version}")
  is_latest_stable=$(is_latest_stable_release "${release_version}" "${repo_owner}")
  is_beta=$(is_beta_release "${release_version}")
  is_patch=$(is_patch_release "${release_version}")
  is_rel_mm=$(is_major_minor "${release_version}")
  [[ "${is_beta}" == "true" ]] && is_rel_mm="false"

  mc_version=$(get_latest_mc_version)

  jq -n \
    --arg mv "$master_ver" \
    --arg mmm "$master_mm" \
    --arg rmm "$rel_mm" \
    --arg mcv "$mc_version" \
    --arg ilsr "$is_latest_stable" \
    --arg ibr "$is_beta" \
    --arg irm "$is_rel_mm" \
    --arg ip "$is_patch" \
    '{
      "master-version": $mv,
      "master-major-minor": $mmm,
      "rel-major-minor": $rmm,
      "mc-version": $mcv,
      "is-latest-stable-release": $ilsr,
      "is-beta-release": $ibr,
      "is-rel-major-minor": $irm,
      "is-patch": $ip
    }' > "${output_file}"

  log_version_variables "${output_file}"
  return 0
}

function load_version_json() {
  local json_file=$1

  if [[ ! -f "${json_file}" ]]; then
    echoerr "❌ Failed to find version info file"
    exit 1
  fi

  jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "${json_file}" >> "${GITHUB_OUTPUT}"
  
  log_version_variables "${json_file}"
  return 0
}
