source /dev/stdin <<< "$(curl --fail --retry 5 --retry-all-errors --show-error --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

# Gets EE POM '<version>' from master and verifies
function get_master_version() {
  local repo_owner=$1

  # Use 'xq' to extract the exact <version> XML node
  local version
  version=$(
    gh api \
      -H "Accept: application/vnd.github.raw+json" \
      "repos/${repo_owner}/hazelcast-mono/contents/pom.xml?ref=master" | \
    xq --raw-output '.project.version // empty'
  )

  if [[ -z "${version}" ]]; then
    echoerr "The 'project.version' element not found or is empty in the POM"
    return 1
  fi

  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.0-SNAPSHOT$ ]]; then
    echoerr "'${version}' is invalid. Must be 'x.y.0-SNAPSHOT'"
    return 1
  fi

  echo "${version}"
  return 0
}

# Return `true` if current release is `latest` by comparing with LATEST_HZ_VERSION
function is_latest_stable_release() {
  local release_ver=$1

  if [[ $(get_major_minor_parts "${release_ver}") == $(get_major_minor_parts "${LATEST_HZ_VERSION}") ]]; then
    echo "true"
  else
    echo "false"
  fi
  
  return 0
}

# Returns `true` if release version contains `BETA`
function is_beta_release() {
  local version=$1
  [[ "${version}" =~ -BETA-[0-9]+$ ]] && echo "true" || echo "false"
  return 0
}

# Returns `true` if `x.y.patch` is 0
function is_major_minor() {
  local version=$1
  local parts=($(get_version_parts "${version}"))
  [[ "${parts[2]}" == "0" ]] && echo "true" || echo "false"
  return 0
}

# Returns `true` if `x.y.patch` is >0
function is_patch_release() {
  local version=$1
  local parts=($(get_version_parts "${version}"))
  [[ "${parts[2]}" -gt 0 ]] && echo "true" || echo "false"
  return 0
}

# Returns `x.y.z` parts of the release version (ignores pre-release IDs) 
function get_version_parts() {
  local release_ver=$1
  local clean_version=${release_ver%%[-+]*}
  echo ${clean_version//./ }
  return 0
}

# Returns `x.y` parts of the release version
function get_major_minor_parts() {
  local release_ver=$1
  local version_parts=($(get_version_parts ${release_ver}))
  echo ${version_parts[0]}.${version_parts[1]}
  return 0
}

# Resolves and outputs various release info variables
function set_rel_info_outputs() {
  local release_version=$1
  local repo_owner=$2

  validate_input_env_variables

  local master_version
  local master_major_minor
  master_version=$(get_master_version "${repo_owner}")
  master_major_minor=$(get_major_minor_parts "${master_version}")

  local release_major_minor
  local is_latest_stable
  local is_beta
  local is_release_major_minor
  local is_patch
  
  release_major_minor=$(get_major_minor_parts "${release_version}")
  is_latest_stable=$(is_latest_stable_release "${release_version}")
  is_beta=$(is_beta_release "${release_version}")
  is_patch=$(is_patch_release "${release_version}")
  is_release_major_minor=$(is_major_minor "${release_version}")
  [[ "${is_beta}" == "true" ]] && is_release_major_minor="false"

  local mc_version
  local mc_major_minor
  mc_version="${LATEST_MC_RELEASE}"
  mc_major_minor=$(get_major_minor_parts "${mc_version}")

  {
    echo "master-version=${master_version}"
    echo "master-major-minor=${master_major_minor}"
    echo "rel-major-minor=${release_major_minor}"
    echo "mc-version=${mc_version}"
    echo "mc-major-minor=${mc_major_minor}"
    echo "is-latest-stable-release=${is_latest_stable}"
    echo "is-beta-release=${is_beta}"
    echo "is-rel-major-minor=${is_release_major_minor}"
    echo "is-patch-release=${is_patch}"
  } >> "${GITHUB_OUTPUT}"

  local longest_key="is-latest-stable-release"
  local padding_size=${#longest_key}
  local log_format="  %-${padding_size}s : %s\n"

  echo "========================================="
  echo "   SET-REL-INFO-OUTPUTS VARIABLES"
  echo "========================================="
  printf "${log_format}" "master-version" "${master_version}"
  printf "${log_format}" "master-major-minor" "${master_major_minor}"
  printf "${log_format}" "rel-major-minor" "${release_major_minor}"
  printf "${log_format}" "mc-version" "${mc_version}"
  printf "${log_format}" "mc-major-minor" "${mc_major_minor}"
  printf "${log_format}" "is-beta-release" "${is_beta}"
  printf "${log_format}" "is-rel-major-minor" "${is_release_major_minor}"
  printf "${log_format}" "is-patch-release" "${is_patch}"
  printf "${log_format}" "is-latest-stable-release" "${is_latest_stable}"
  echo "========================================="

  return 0
}

# Checks expected input env vars are set. These will be passed in by the action
function validate_input_env_variables() {
  if [[ -z "${LATEST_MC_RELEASE:-}" ]]; then
    echoerr "❌ Error: LATEST_MC_RELEASE environment variable is missing or empty."
    exit 1
  fi

  if [[ -z "${LATEST_HZ_VERSION:-}" ]]; then
    echoerr "❌ Error: LATEST_HZ_VERSION environment variable is missing or empty."
    exit 1
  fi

  return 0
}
