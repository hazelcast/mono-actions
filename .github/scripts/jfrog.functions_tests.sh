#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail ${RUNNER_DEBUG:+-x}

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Source the latest version of assert.sh unit testing library and include in current shell
source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/assert.sh/main/assert.sh)"

# source script under test
source "${SCRIPT_DIR}/../../invoke-jfrog-cli/scripts/jfrog.functions.sh"

# Global test constant to eliminate Sonar duplication warnings
readonly EMPTY_ITEMS_PAYLOAD='{"items": []}'

# Temp files to save mocked 'jf' inputs/outputs
MOCK_ARGS_FILE="${SCRIPT_DIR}/.mock_args"
MOCK_STDIN_FILE="${SCRIPT_DIR}/.mock_stdin"
MOCK_STDOUT_FILE="${SCRIPT_DIR}/.mock_stdout"

trap 'rm -f "${MOCK_ARGS_FILE}" "${MOCK_STDIN_FILE}" "${MOCK_STDOUT_FILE}"' EXIT

function jf() {
  echo "$*" > "${MOCK_ARGS_FILE}"
  cat > "${MOCK_STDIN_FILE}"
  if [[ -f "${MOCK_STDOUT_FILE}" ]]; then
    cat "${MOCK_STDOUT_FILE}"
  fi
  return 0
}

# Mock 'jf' client which overrides the 'jf' command
export -f jf

TESTS_RESULT=0

function reset_mocks() {
  echo -n "" > "${MOCK_ARGS_FILE}"
  echo -n "" > "${MOCK_STDIN_FILE}"
  echo '{"status": "success", "totals": {"success": 4, "failure": 0}}' > "${MOCK_STDOUT_FILE}"
  return 0
}

function get_jfrog_cli_default_options() {
  local cmd="$1"
  local threads="${2:-4}"
  echo "rt ${cmd} --fail-no-op --format=json --flat --threads ${threads}"
  return 0
}

function test_jfrog_cli_download_by_file() {
  log_header "Testing jfrog_cli_download_by_file"
  reset_mocks
  echo '{"status": "success", "totals": {"success": 1, "failure": 0}}' > "${MOCK_STDOUT_FILE}"

  local target_dir="tmp/downloads"
  local url="https://example.com"
  
  jfrog_cli_download_by_file "${target_dir}" "${url}" 1 "" "true"
  local actual_exit_code=$?

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local actual_stdin=$(cat "${MOCK_STDIN_FILE}")

  local msg="jfrog_cli_download_by_file finished with exit code 0"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local expected_args="$(get_jfrog_cli_default_options "${CMD_DOWNLOAD}") --build-name=false --build-number=false --explode ${url} ${target_dir}/"
  local msg="Direct file options formatting parameters match"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local msg="Passed empty payload via stdin channel"
  assert_eq "" "${actual_stdin}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_cli_download_by_aql() {
  log_header "Testing jfrog_cli_download_by_aql"
  reset_mocks

  local payload='{"items": [{"name": "hz-distribution"}]}'
  local spec_vars="VERSION=5.11.0"

  jfrog_cli_download_by_aql "${payload}" "${spec_vars}" 4
  local actual_exit_code=$?

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local actual_stdin=$(cat "${MOCK_STDIN_FILE}")

  local msg="jfrog_cli_download_by_aql finished with exit code 0"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local expected_args="$(get_jfrog_cli_default_options "${CMD_DOWNLOAD}") --spec /dev/stdin --spec-vars=${spec_vars}"
  local msg="AQL specification options structural parameters match"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local msg="Piped explicit AQL payload directly to standard input channel"
  assert_eq "${payload}" "${actual_stdin}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_cli_copy_by_aql() {
  log_header "Testing jfrog_cli_copy_by_aql"
  reset_mocks

  local payload='{"items": [{"name": "hz-enterprise"}]}'
  local spec_vars="TARGET=prod"

  jfrog_cli_copy_by_aql "${payload}" "${spec_vars}" 4
  local actual_exit_code=$?

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local actual_stdin=$(cat "${MOCK_STDIN_FILE}")

  local msg="jfrog_cli_copy_by_aql finished with exit code 0"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local expected_args="$(get_jfrog_cli_default_options 'copy') --spec /dev/stdin --spec-vars=${spec_vars}"
  local msg="Copy operational specification formatting layout matches"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  
  local msg="Mirrored explicit target payload layout"
  assert_eq "${payload}" "${actual_stdin}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_cli_upload_by_file() {
  log_header "Testing jfrog_cli_upload_by_file"
  reset_mocks
  echo '{"status": "success", "totals": {"success": 3, "failure": 0}}' > "${MOCK_STDOUT_FILE}"

  local target_repo_path="sandbox-repo/target-path"
  local source_pattern="tmp/upload-dir/*"

  jfrog_cli_upload_by_file "${target_repo_path}" "${source_pattern}" 3
  local actual_exit_code=$?

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local actual_stdin=$(cat "${MOCK_STDIN_FILE}")

  local msg="jfrog_cli_upload_by_file finished with exit code 0"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local expected_args="$(get_jfrog_cli_default_options 'upload') ${source_pattern} ${target_repo_path}/"
  local msg="Upload file options formatting parameters match"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  local msg="Passed empty payload via stdin channel for file upload"
  assert_eq "" "${actual_stdin}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_assert_failure_flow() {
  log_header "Testing strict count assertion failure scenario"
  reset_mocks
  echo '{"status": "success", "totals": {"success": 2, "failure": 0}}' > "${MOCK_STDOUT_FILE}"

  local payload="${EMPTY_ITEMS_PAYLOAD}"
  
  (jfrog_cli_download_by_aql "${payload}" "" 4 2>/dev/null) && true
  local actual_exit_code=$?

  local msg="Wrapper pipeline terminated with error code status 1 when threshold was missed"
  assert_eq 1 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_skip_assertion_flow() {
  log_header "Testing assertion skip flow configuration"
  reset_mocks
  echo '{"status": "success", "totals": {"success": 99, "failure": 0}}' > "${MOCK_STDOUT_FILE}"

  local payload="${EMPTY_ITEMS_PAYLOAD}"

  jfrog_cli_download_by_aql "${payload}" "" ""
  local actual_exit_code=$?

  local msg="Processed cleanly without executing strict count constraints checks"
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_thread_count_parameter_override() {
  log_header "Testing explicit thread count parameter override"
  reset_mocks

  local payload="${EMPTY_ITEMS_PAYLOAD}"
  local spec_vars=""
  local expected_count=""
  local custom_threads=8

  jfrog_cli_download_by_aql "${payload}" "${spec_vars}" "${expected_count}" "${custom_threads}"

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local expected_args="$(get_jfrog_cli_default_options "${CMD_DOWNLOAD}" "${custom_threads}") --spec /dev/stdin --spec-vars="
  local msg="Explicit thread count parameter overrides default value"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

function test_jfrog_thread_count_env_override() {
  log_header "Testing DEFAULT_JF_CLI_THREAD_COUNT environment variable override"
  reset_mocks

  local payload="${EMPTY_ITEMS_PAYLOAD}"
  export DEFAULT_JF_CLI_THREAD_COUNT=16

  jfrog_cli_download_by_aql "${payload}" "" ""

  local actual_args=$(cat "${MOCK_ARGS_FILE}")
  local expected_args="$(get_jfrog_cli_default_options "${CMD_DOWNLOAD}" "${DEFAULT_JF_CLI_THREAD_COUNT}") --spec /dev/stdin --spec-vars="
  local msg="Global environment variable definitions override fallback default constants"
  assert_eq "${expected_args}" "${actual_args}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?

  return "${TESTS_RESULT}"
}

# --- Execution Entrypoint ---
test_jfrog_cli_download_by_file
test_jfrog_cli_download_by_aql
test_jfrog_cli_copy_by_aql
test_jfrog_cli_upload_by_file
test_jfrog_assert_failure_flow
test_jfrog_skip_assertion_flow
test_jfrog_thread_count_parameter_override
test_jfrog_thread_count_env_override

assert_eq 0 "${TESTS_RESULT}" "All tests should pass"
