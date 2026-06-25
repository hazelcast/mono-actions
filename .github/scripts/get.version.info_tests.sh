#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail ${RUNNER_DEBUG:+-x}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/assert.sh/main/assert.sh)"
source "${SCRIPT_DIR}/../../get-version-info/scripts/get.version.info.sh"

MOCK_GH_ARGS_FILE="${SCRIPT_DIR}/.mock_gh_args"
MOCK_GH_STDOUT_FILE="${SCRIPT_DIR}/.mock_gh_stdout"

readonly TEST_REPO="my-repo"

trap 'rm -f "${MOCK_GH_ARGS_FILE}" "${MOCK_GH_STDOUT_FILE}"' EXIT

function gh() {
  echo "$*" > "${MOCK_GH_ARGS_FILE}"
  if [[ -f "${MOCK_GH_STDOUT_FILE}" ]]; then
    cat "${MOCK_GH_STDOUT_FILE}"
  fi
  return 0
}
export -f gh

function cd() {
  return 0
}

function get_project_version() {
  echo "${MOCK_POM_VERSION:-5.4.0}"
  return 0
}
export -f get_project_version

function curl() {
  echo "# MOCK - Skipped downloading external script asset"
  return 0
}
export -f curl

TESTS_RESULT=0

function reset_mocks() {
  echo -n "" > "${MOCK_GH_ARGS_FILE}"
  rm -f "${MOCK_GH_STDOUT_FILE}"
  MOCK_POM_VERSION="5.4.0"
  return 0
}

function test_is_major_minor() {
  log_header "Testing is_major_minor"
  reset_mocks

  local actual msg

  actual=$(is_major_minor "5.4.0")
  msg="Returns true when patch version is exactly 0"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_major_minor "5.4.1")
  msg="Returns false when patch version is greater than 0"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_major_minor "6.0.0-BETA-1")
  msg="Returns true for beta versions with a 0 patch"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_patch_release() {
  log_header "Testing is_patch_release"
  reset_mocks

  local actual msg

  actual=$(is_patch_release "5.4.1")
  msg="Returns true when patch version is greater than 0"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_patch_release "5.4.0")
  msg="Returns false when patch version is exactly 0"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_patch_release "5.4.3-BETA-2")
  msg="Returns true for beta versions with a non-zero patch"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

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

function test_get_version_parts() {
  log_header "Testing get_version_parts"
  reset_mocks

  local actual msg

  actual=$(get_version_parts "5.4.3")
  msg="Extracts components cleanly into space separated items"
  assert_eq "5 4 3" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(get_version_parts "5.4.0-BETA-1")
  msg="Strips off beta suffix elements completely"
  assert_eq "5 4 0" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_get_major_minor_parts() {
  log_header "Testing get_major_minor_parts"
  reset_mocks

  local actual msg

  actual=$(get_major_minor_parts "5.4.3")
  msg="Isolates and outputs exactly major.minor layout"
  assert_eq "5.4" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(get_major_minor_parts "6.0.0-BETA-2")
  msg="Discards metadata segments safely during layout mapping"
  assert_eq "6.0" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_release_next_major() {
  log_header "Testing is_release_next_major"
  reset_mocks

  local actual msg

  MOCK_POM_VERSION="7.0.0"
  actual=$(is_release_next_major "${TEST_REPO}" "6.0.0")
  msg="Returns true when pom major is higher (7.0.0) and minor/patch are 0.0"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  MOCK_POM_VERSION="6.1.0"
  actual=$(is_release_next_major "${TEST_REPO}" "5.4.0")
  msg="Returns false if pom major is higher but minor version is non-zero"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  MOCK_POM_VERSION="5.4.0"
  actual=$(is_release_next_major "${TEST_REPO}" "5.4.0")
  msg="Returns false when version milestones match exactly"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  MOCK_POM_VERSION="100.0.0"
  actual=$(is_release_next_major "${TEST_REPO}" "99.1.0")
  msg="Returns true when pom version is 100.0.0 and release version is 99.1.0"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  MOCK_POM_VERSION="5.6.0"
  actual=$(is_release_next_major "${TEST_REPO}" "3.2.1")
  msg="Returns false when pom version is 5.6.0 and release version is 3.2.1"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_latest_stable_release() {
  log_header "Testing is_latest_stable_release"
  reset_mocks

  local actual msg

  printf '%s\n' "5.3.z" "5.4.z" "5.4.z" > "${MOCK_GH_STDOUT_FILE}"

  actual=$(is_latest_stable_release "5.4.0" "${TEST_REPO}")
  msg="Returns true when passed version matches highest stable branch minor layout"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  actual=$(is_latest_stable_release "5.3.0" "${TEST_REPO}")
  msg="Returns false when evaluating older stable branch targets"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  printf '%s\n' "5.3.z" "5.4.z" "5.4.z" "99.1.z" > "${MOCK_GH_STDOUT_FILE}"
  actual=$(is_latest_stable_release "99.1.0" "${TEST_REPO}")
  msg="Returns true when passed version major.minor matches highest stable tag"
  assert_eq "true" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  printf '%s\n' "5.6.z" "5.5.z" > "${MOCK_GH_STDOUT_FILE}"
  actual=$(is_latest_stable_release "3.2.1" "${TEST_REPO}")
  msg="Returns false when passed version major.minor does not match highest stable tag"
  assert_eq "false" "${actual}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_is_latest_stable_release_error() {
  log_header "Testing is_latest_stable_release error handling"
  reset_mocks

  echo -n "" > "${MOCK_GH_STDOUT_FILE}"

  local actual_stderr
  actual_stderr=$( (is_latest_stable_release "5.4.0" "${TEST_REPO}") 2>&1 >/dev/null ) && actual_exit_code=0 || actual_exit_code=$?

  local msg="Function returns exit status code 1 when latest_stable cannot be resolved"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Error string printed to stderr matches formatting parameters layout"
  local expected_err="::error::ERROR - ❌ Failed to resolve 'latest_stable' from repository '${TEST_REPO}/hazelcast-mono'."
  assert_eq "${expected_err}" "${actual_stderr}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

test_is_major_minor
test_is_patch_release
test_is_beta_release
test_get_version_parts
test_get_major_minor_parts
test_is_release_next_major
test_is_latest_stable_release
test_is_latest_stable_release_error

assert_eq 0 "${TESTS_RESULT}" "All tests should pass"
