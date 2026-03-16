#!/bin/bash

set -o errexit -o nounset

# Source the latest version of assert.sh unit testing library and include in current shell
source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/assert.sh/main/assert.sh)"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}"/maven.functions.sh

TESTS_RESULT=0

function assert_get_maven_artifact {
  local group_id=$1
  local artifact_id=$2
  local artifact_version=$3
  local remote_repositories=$4
  local output
  output=$(get_maven_artifact "${group_id}" "${artifact_id}" "${artifact_version}" "${remote_repositories}" && true)
  actual_exit_code=$?
  local msg="Expected to download of ${group_id}:${artifact_id}:${artifact_version} to finish sucessfully - exit code - \"${actual_exit_code}\", output - \"${output}\""
  assert_eq 0 "${actual_exit_code}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
  local msg="Expected to find downloaded version of ${group_id}:${artifact_id}:${artifact_version} at \"${output}\""
  [[ -f "${output}" ]] && true
  assert_eq 0 $? "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
}

function assert_get_jdk_version {
  local out=$(get_jdk_version)
  local msg="JDK version not found"
  assert_not_empty "${out}" "${msg}" && log_success "${msg}" || TESTS_RESULT=$?
}

log_header "Tests for get_maven_artifact"
assert_get_maven_artifact  "com.google.guava" "listenablefuture" "9999.0-empty-to-avoid-conflict-with-guava" "https://repo1.maven.org/maven2"
# https://github.com/hazelcast/hazelcast/issues/25451#issuecomment-1720248676/
MAVEN_OPTS="-verbose:gc" assert_get_maven_artifact  "com.google.guava" "listenablefuture" "9999.0-empty-to-avoid-conflict-with-guava" "https://repo1.maven.org/maven2"

log_header "Tests for get_jdk_version"
assert_get_jdk_version

assert_eq 0 "${TESTS_RESULT}" "All tests should pass"

