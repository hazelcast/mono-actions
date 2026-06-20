source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

# Default JFrog CLI thread count for concurrency. Use a different thread count
# before calling any functions (where applicable):
#
#  1. Pass in the value (thread_count) to the function, or
#  2. Set environment variable 'DEFAULT_JF_CLI_THREAD_COUNT'.
#
# Note: Custom default tailored for website assets handling. JFrog CLI default is 3

: "${DEFAULT_JF_CLI_THREAD_COUNT:=4}"

# For Sonar
readonly CMD_DOWNLOAD='download'

# Downloads multiple files using supplied JSON AQL. The caller should ensure AQL
# is correctly formatted. Supply 'spec_vars' for variable replacements in the AQL.
# See:
#   1. https://docs.jfrog.com/artifactory/docs/generic-files#downloading-files
#   2. https://docs.jfrog.com/artifactory/docs/using-file-specs
function jfrog_cli_download_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-}"
  local explode="${5:-false}"

  local opts=()
  opts+=($(__get_jf_options "aql" "${CMD_DOWNLOAD}" "${spec_vars}" "${thread_count}" "${explode}"))
  __execute_jf_command "${aql_payload}" "${CMD_DOWNLOAD}" "${expected_count}" "${opts[@]}"
  return $?
}

# Downloads one or more files depending on 'file_payload'. This can be an exact filename or pattern
# e.g. 'libs-release-local/*.jar'. Only '?' and '*' wildcards are supported. For more complex
# patterns (e.g. multiple files with different extensions), use AQL instead for precision.
# See https://docs.jfrog.com/artifactory/docs/generic-files#downloading-files
function jfrog_cli_download_by_file() {
  local target_dir="$1"
  local file_payload="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-}"
  local explode="${5:-false}"

  local opts=()
  opts+=($(__get_jf_options "file" "${CMD_DOWNLOAD}" "" "${thread_count}" "${explode}"))
  __execute_jf_command "" "${CMD_DOWNLOAD}" "${expected_count}" "${opts[@]}" "${file_payload}" "${target_dir}/"
  return $?
}

# Copies repository files directly on the server side using AQL. This is more efficient compared to
# downloading and re-uploading.
# See https://docs.jfrog.com/artifactory/docs/generic-files#copying-files
function jfrog_cli_copy_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-}"
  local explode="${5:-false}"

  local opts=()
  opts+=($(__get_jf_options "aql" "copy" "${spec_vars}" "${thread_count}" "${explode}"))
  __execute_jf_command "${aql_payload}" "copy" "${expected_count}" "${opts[@]}"
  return $?
}

# Uploads one or more local files to a target JFrog repository path. Use 'source_file_pattern'
# with:
#   1. Exact filename
#   2. Basic wildcards '?' or '*'
#   3. Capture groups e.g. '/tmp/my-files/(*)-(*).zip'
#   4. Pipe matching e.g. (*.zip|*.tar.gz)
#
# Note: The Upload command also supports '--regexp' but it is not used at the moment!
#
# See https://docs.jfrog.com/artifactory/docs/generic-files#uploading-files
function jfrog_cli_upload_by_file() {
  local target_path="$1"
  local local_path="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-$DEFAULT_JF_CLI_THREAD_COUNT}"
  local explode="${5:-false}"

  local opts=()
  opts+=($(__get_jf_options_common "upload" "${thread_count}" "${explode}"))
  __execute_jf_command "" "upload" "${expected_count}" "${opts[@]}" "${local_path}" "${target_path}/"
  return $?
}

# Internal function to return common 'jf' options
function __get_jf_options_common() {
  local cmd_type="$1"
  local thread_count="${2:-$DEFAULT_JF_CLI_THREAD_COUNT}"
  local explode="${3:-false}"
  local opts=()

  opts+=("--fail-no-op")
  opts+=("--format=json")
  opts+=("--flat")
  opts+=("--threads" "${thread_count}")

  if [[ "${explode}" == "true" && "${cmd_type}" =~ ^(${CMD_DOWNLOAD}|upload)$ ]]; then
    opts+=("--explode")
  fi

  echo "${opts[@]}"
  return 0
}

# Internal function to get 'jf' options based on the supplied command mode.
function __get_jf_options() {
  local mode="$1"
  local cmd_type="$2"
  local spec_vars="${3:-}"
  local thread_count="${4:-$DEFAULT_JF_CLI_THREAD_COUNT}"
  local explode="${5:-false}"
  local opts=()

  opts+=($(__get_jf_options_common "${cmd_type}" "${thread_count}" "${explode}"))

  case "${mode}" in
    "aql")
      opts+=("--spec" "/dev/stdin")
      opts+=("--spec-vars=${spec_vars}")
      ;;
    "file")
      opts+=("--build-name=false")
      opts+=("--build-number=false")
      ;;
    *)
      echoerr "❌ Unknown JFrog CLI option mode passed: ${mode}"
      return 1
      ;;
  esac

  echo "${opts[@]}"
  return 0
}


# Internal function to execute the JFrog CLI command
function __execute_jf_command() {
  local stdin_payload="$1"
  local cmd_type="$2"
  local expected_count="$3"
  shift 3

  # The 'stdin_payload' has been named generically to allow AQL or file spec.
  #
  # Passing AQL spec via STDIN is safer - guards against quoting issues etc.
  # If the payload is empty (e.g. when a spec is not needed/supplied), 'jf' will
  # simply not read from STDIN and continue with the command by virtue of not
  # supplying '/dev/stdin' (see __get_jf_options()).

  local jf_output
  jf_output=$(echo "${stdin_payload}" | jf rt "${cmd_type}" "$@")

  if [[ -n "${expected_count}" ]]; then
    local actual_count
    actual_count=$(echo "${jf_output}" | jq '.totals.success')

    if [[ "${actual_count}" -ne "${expected_count}" ]]; then
      echoerr "❌ Expected ${expected_count} files for ${cmd_type}, but completed: ${actual_count}"
      echoerr "${jf_output}"
      exit 1
    fi
  fi

  return 0
}
