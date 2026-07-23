#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail ${RUNNER_DEBUG:+-x}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source /dev/stdin <<< "$(curl --fail --retry 5 --retry-all-errors --show-error --silent https://raw.githubusercontent.com/hazelcast/assert.sh/main/assert.sh)"
source "${SCRIPT_DIR}/../../release-info/scripts/release.info.functions.sh"

TESTS_RESULT=0

readonly MOCK_OWNER="hazelcast"

function reset_mocks() {
  export LATEST_MC_RELEASE="5.12.0"
  export LATEST_HZ_VERSION="5.4.0"

  curl() {
    if [[ "$*" == *"logging.functions.sh"* ]]; then
      echo "function echodebug() { echo \"[DEBUG] \$*\"; }"
      echo "function echoerr() { echo \"\$*\"; >&2; }"
    fi
    return 0
  }
  export -f curl

  gh() {
    if [[ "${MOCK_GH_FAIL:-false}" == "true" ]]; then
      return 1
    fi
    echo '<project><version>5.5.0-SNAPSHOT</version></project>'
    return 0
  }
  export -f gh

  xq() {
    if [[ "$*" == *".project.version // empty"* ]]; then
      echo "5.5.0-SNAPSHOT"
    fi
    return 0
  }
  export -f xq
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
  
  actual=$(is_latest_stable_release "5.4.0")
  msg="Passes version matching LATEST_HZ_VERSION major-minor layout"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_latest_stable_release "5.3.0")
  msg="Fails legacy version sequences against LATEST_HZ_VERSION"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_validate_input_env_variables() {
  log_header "Testing validate_input_env_variables success"
  reset_mocks

  local actual_exit_code=0
  validate_input_env_variables && actual_exit_code=0 || actual_exit_code=$?

  local msg="Validation block passes when expected environment keys are set"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_validate_input_env_variables_error() {
  log_header "Testing validate_input_env_variables error handling"

  # Test LATEST_MC_RELEASE is missing
  reset_mocks
  unset LATEST_MC_RELEASE
  
  local actual_exit_code=0
  (validate_input_env_variables) 2>/dev/null && actual_exit_code=0 || actual_exit_code=$?

  local msg="Checks missing LATEST_MC_RELEASE"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  # Test LATEST_HZ_VERSION is missing
  reset_mocks
  unset LATEST_HZ_VERSION
  
  actual_exit_code=0
  (validate_input_env_variables) 2>/dev/null && actual_exit_code=0 || actual_exit_code=$?

  local msg="Checks missing LATEST_HZ_VERSION"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_set_rel_info_outputs() {
  log_header "Testing set_rel_info_outputs"
  reset_mocks
  truncate -s 0 "${GITHUB_OUTPUT}"

  set_rel_info_outputs "5.4.0" "${MOCK_OWNER}" > /dev/null

  local msg actual

  msg="Computes correct rel-major-minor key inside property file"
  actual=$(grep "^rel-major-minor=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "5.4" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Computes correct mc-version key inside property file"
  actual=$(grep "^mc-version=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "5.12.0" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Computes correct mc-major-minor key inside property file"
  actual=$(grep "^mc-major-minor=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "5.12" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Assigns false to is-beta-release field"
  actual=$(grep "^is-beta-release=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Resolves true for is-rel-major-minor property"
  actual=$(grep "^is-rel-major-minor=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  msg="Flags is-patch-release accurately to false"
  actual=$(grep "^is-patch-release=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  truncate -s 0 "${GITHUB_OUTPUT}"
  set_rel_info_outputs "5.4.0-BETA-1" "${MOCK_OWNER}" > /dev/null

  msg="Beta Path: Forces is-rel-major-minor property to false"
  actual=$(grep "^is-rel-major-minor=" "${GITHUB_OUTPUT}" | cut -d'=' -f2 | xargs)
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

# --- Run test suites ---
test_get_version_parts
test_get_major_minor_parts
test_is_beta_release
test_is_major_minor
test_is_patch_release
test_is_latest_stable_release
test_validate_input_env_variables
test_validate_input_env_variables_error
test_set_rel_info_outputs

assert_eq 0 "${TESTS_RESULT}" "All tests should pass"
