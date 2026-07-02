#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail ${RUNNER_DEBUG:+-x}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/assert.sh/main/assert.sh)"
source "${SCRIPT_DIR}/../../release-info/scripts/release.info.sh"

# Global Test Status Tracking Flag
TESTS_RESULT=0

function reset_mocks() {
  curl() {
    if [[ "$*" == *"logging.functions.sh"* ]]; then
      echo "function echodebug() { echo \"[DEBUG] \$*\"; }"
      echo "function echoerr() { echo \"\$*\"; >&2; }"
    elif [[ "$*" == *"maven.functions.sh"* ]]; then
      echo "function get_project_version() { echo \"5.5.0-SNAPSHOT\"; }"
    fi
    return 0
  }
  export -f curl

  gh() {
    if [[ "${MOCK_GH_FAIL:-false}" == "true" ]]; then
      return 0
    fi
    if [[ "$*" == *"branches"* ]]; then
      echo "5.3.z"
      echo "5.4.z"
      echo "5.2.z"
    elif [[ "$*" == *"tags"* ]]; then
      echo "5.11.0"
      echo "5.12.0"
      echo "5.1.0"
    fi
    return 0
  }
  export -f gh
}

TEST_TEMP_DIR=$(mktemp -d)
export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output.txt"
touch "${GITHUB_OUTPUT}"

trap 'rm -rf "${TEST_TEMP_DIR}"' EXIT


function test_get_version_parts() {
  log_header "Testing get_version_parts"
  reset_mocks

  local parts msg
  parts=($(get_version_parts "5.4.1-BETA-2"))
  
  msg="Correctly extracts major version element"
  assert_eq "5" "${parts[0]}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Correctly extracts minor version element"
  assert_eq "4" "${parts[1]}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Correctly extracts patch version element"
  assert_eq "1" "${parts[2]}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_get_major_minor_parts() {
  log_header "Testing get_major_minor_parts"
  reset_mocks

  local actual msg
  
  actual=$(get_major_minor_parts "5.4.3-patch")
  msg="Correctly resolves first two version digits"
  assert_eq "5.4" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_beta_release() {
  log_header "Testing is_beta_release"
  reset_mocks

  local actual msg
  
  actual=$(is_beta_release "5.3.0-BETA-1")
  msg="Correctly flags standard hyphen-suffixed beta string as true"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_beta_release "5.3.0-BETA-12")
  msg="Correctly handles multi-digit beta identifiers as true"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_beta_release "5.3.0-BETA")
  msg="Flags string missing a numeric trailing index as false"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_beta_release "5.3.0-SNAPSHOT")
  msg="Ignores alternative release variants like SNAPSHOT as false"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_major_minor() {
  log_header "Testing is_major_minor"
  reset_mocks

  local actual msg
  
  actual=$(is_major_minor "5.4.0")
  msg="Flags clean major-minor base version as true"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_major_minor "5.4.1")
  msg="Rejects non-zero patch increments as false"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_patch_release() {
  log_header "Testing is_patch_release"
  reset_mocks

  local actual msg
  
  actual=$(is_patch_release "5.4.1")
  msg="Identifies active patch versions above zero as true"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_patch_release "5.4.0")
  msg="Rejects base major-minor versions as false"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_latest_stable_release() {
  log_header "Testing is_latest_stable_release"
  reset_mocks

  local actual msg
  
  actual=$(is_latest_stable_release "5.4.0" "hazelcast")
  msg="Passes version matching the highest simulated remote branch"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_latest_stable_release "5.3.0" "hazelcast")
  msg="Fails legacy version sequences against remote branches"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_latest_stable_release_error() {
  log_header "Testing is_latest_stable_release error handling"
  
  local MOCK_GH_FAIL="true"
  export MOCK_GH_FAIL
  reset_mocks

  local actual_stderr actual_exit_code
  actual_stderr=$( (is_latest_stable_release "5.4.0" "hazelcast") 2>&1 >/dev/null ) && actual_exit_code=0 || actual_exit_code=$?

  local msg="Function returns exit status code 1 when latest_stable cannot be resolved"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Error string printed to stderr matches formatting parameters layout"
  local expected_err="::error::ERROR - ❌ Failed to resolve 'latest_stable' from repository 'hazelcast/hazelcast-mono'."
  assert_eq "${expected_err}" "${actual_stderr}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_generate_rel_info_json() {
  log_header "Testing generate_rel_info_json"
  reset_mocks

  local out_json fake_mono msg
  out_json="${TEST_TEMP_DIR}/release_stable.json"
  fake_mono="${TEST_TEMP_DIR}/mono-repo"
  mkdir -p "${fake_mono}"

  generate_rel_info_json "${out_json}" "5.4.0" "hazelcast" "${fake_mono}" 2>&1 | grep -v "::debug::" || true
  
  msg="Generate: Creates physical destination JSON file on disk"
  [[ -f "${out_json}" ]] && log_success "${msg}" || { echo "✖ ${msg}"; TESTS_RESULT=1; }

  msg="Generate: Computes correct rel-major-minor key inside JSON"
  assert_eq "5.4" "$(jq -r '."rel-major-minor"' "${out_json}")" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Generate: Assigns false to is-beta-release field"
  assert_eq "false" "$(jq -r '."is-beta-release"' "${out_json}")" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Generate: Resolves true for is-rel-major-minor property"
  assert_eq "true" "$(jq -r '."is-rel-major-minor"' "${out_json}")" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Generate: Flags is-patch accurately to false"
  assert_eq "false" "$(jq -r '."is-patch"' "${out_json}")" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local out_beta_json="${TEST_TEMP_DIR}/release_beta.json"
  
  generate_rel_info_json "${out_beta_json}" "5.4.0-BETA-1" "hazelcast" "${fake_mono}" 2>&1 | grep -v "::debug::" || true

  msg="Beta Path: Forces is-rel-major-minor property to false"
  assert_eq "false" "$(jq -r '."is-rel-major-minor"' "${out_beta_json}")" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_load_version_json() {
  log_header "Testing load_version_json"
  reset_mocks

  local mock_input msg
  mock_input="${TEST_TEMP_DIR}/mock_input.json"
  truncate -s 0 "${GITHUB_OUTPUT}"
  
  echo '{
    "master-version": "5.5.0",
    "is-patch": "true"
  }' > "${mock_input}"

  load_version_json "${mock_input}" > /dev/null 2>&1

  msg="Load: Properly appends master-version variable mapping to GITHUB_OUTPUT channel"
  grep -q "master-version=5.5.0" "${GITHUB_OUTPUT}" && log_success "${msg}" || { echo "✖ ${msg}"; TESTS_RESULT=1; }

  msg="Load: Properly appends is-patch variable mapping to GITHUB_OUTPUT channel"
  grep -q "is-patch=true" "${GITHUB_OUTPUT}" && log_success "${msg}" || { echo "✖ ${msg}"; TESTS_RESULT=1; }

  return "${TESTS_RESULT}"
}

function test_get_latest_mc_version() {
  log_header "Testing get_latest_mc_version"
  reset_mocks

  local actual msg

  actual=$(get_latest_mc_version)
  msg="Correctly fetches latest stable version from GitHub tags and strips the leading v"
  assert_eq "5.12.0" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_get_latest_mc_version_error() {
  log_header "Testing get_latest_mc_version error handling"
  
  local MOCK_GH_FAIL="true"
  export MOCK_GH_FAIL
  reset_mocks

  local actual_stderr actual_exit_code
  actual_stderr=$( (get_latest_mc_version) 2>&1 >/dev/null ) && actual_exit_code=0 || actual_exit_code=$?

  local msg="Function returns exit status code 1 when mc tags cannot be resolved"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Error string printed to stderr matches mc error layout"
  local expected_err="::error::ERROR - ❌ Failed to get latest MC ZIP from GitHub"
  assert_eq "${expected_err}" "${actual_stderr}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_get_latest_mc_version() {
  log_header "Testing get_latest_mc_version"
  reset_mocks

  local actual msg

  actual=$(get_latest_mc_version)
  msg="Correctly fetches latest stable version from GitHub tags and strips the leading v"
  assert_eq "5.12.0" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_get_latest_mc_version_error() {
  log_header "Testing get_latest_mc_version error handling"
  
  local MOCK_GH_FAIL="true"
  export MOCK_GH_FAIL
  reset_mocks

  local actual_stderr actual_exit_code
  actual_stderr=$( (get_latest_mc_version) 2>&1 >/dev/null ) && actual_exit_code=0 || actual_exit_code=$?

  local msg="Function returns exit status code 1 when mc tags cannot be resolved"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Error string printed to stderr matches mc error layout"
  local expected_err="::error::ERROR - ❌ Failed to get latest MC ZIP from GitHub"
  assert_eq "${expected_err}" "${actual_stderr}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_load_version_json_error() {
  log_header "Testing load_version_json error handling"
  reset_mocks

  local actual_stderr actual_exit_code
  actual_stderr=$( (load_version_json "non_existent_file.json") 2>&1 >/dev/null ) && actual_exit_code=0 || actual_exit_code=$?

  local msg="Function returns exit status code 1 when target JSON file does not exist"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Error string printed to stderr matches JSON missing file error layout"
  local expected_err="::error::ERROR - ❌ Failed to find version info file"
  assert_eq "${expected_err}" "${actual_stderr}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

# ==========================
# MAIN SUITE EXECUTION DRIVE
# ==========================
test_get_version_parts
test_get_major_minor_parts
test_is_beta_release
test_is_major_minor
test_is_patch_release
test_is_latest_stable_release
test_is_latest_stable_release_error
test_generate_rel_info_json
test_get_latest_mc_version
test_get_latest_mc_version_error
test_load_version_json
test_load_version_json_error

assert_eq 0 "${TESTS_RESULT}" "All tests should pass"
