source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

# Default 'jf' cli thread count for concurrency. Use different thread count
# before calling any functions (where applicable):
#
#  1. pass in the value (thread_count) to the function, or
#  2. set environment variable 'DEFAULT_JF_CLI_THREAD_COUNT'

: "${DEFAULT_JF_CLI_THREAD_COUNT:=4}"

function jfrog_cli_download_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  local cmd_type="${4:-download}"
  local thread_count="${5:-$DEFAULT_JF_CLI_THREAD_COUNT}"

  __execute_jf_command "${aql_payload}" "${cmd_type}" "${expected_count}" $(__get_jf_options "aql" "${spec_vars}" "${thread_count}")
}

function jfrog_cli_download_by_file() {
  local target_dir="$1"
  local file_payload="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-$DEFAULT_JF_CLI_THREAD_COUNT}"

  __execute_jf_command "" "download" "${expected_count}" $(__get_jf_options "file" "" "${thread_count}") "${file_payload}" "${target_dir}/"
}

function jfrog_cli_copy_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-$DEFAULT_JF_CLI_THREAD_COUNT}"

  jfrog_cli_download_by_aql "${aql_payload}" "${spec_vars}" "${expected_count}" "copy" "${thread_count}"
}

function jfrog_cli_upload_by_file() {
  local target_repo_path="$1"
  local source_file_pattern="$2"
  local expected_count="${3:-}"
  local thread_count="${4:-$DEFAULT_JF_CLI_THREAD_COUNT}"

  __execute_jf_command "" "upload" "${expected_count}" $(__get_jf_options "upload" "" "${thread_count}") "${source_file_pattern}" "${target_repo_path}/"
}

function jq_extract_json_aql() {
  local aql_json_string="$1"
  local target_key="$2"
  echo "${aql_json_string}" | jq --raw-output --arg target "${target_key}" '.[$target] | tostring'
}

function __get_jf_options() {
  local mode="$1"
  local spec_vars="${2:-}"
  local thread_count="$3"
  local opts=()

  opts+=("--fail-no-op")
  opts+=("--format=json")
  opts+=("--threads" "${thread_count}")

  case "${mode}" in
    "aql")
      opts+=("--spec" "/dev/stdin")
      opts+=("--spec-vars=${spec_vars}")
      ;;
    "upload")
      opts+=("--flat")
      ;;
    "file")
      opts+=("--build-name=false")
      opts+=("--build-number=false")
      opts+=("--flat")
      opts+=("--explode")
      ;;
    *)
      echoerr "❌ Error: Unknown JFrog CLI option mode passed: ${mode}"
      exit 1
      ;;
  esac

  echo "${opts[@]}"
}

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
  # supplying '/dev/stdin' (see __get_jf_options())

  local jf_output
  jf_output=$(echo "${stdin_payload}" | jf rt "${cmd_type}" "$@")

  if [[ -n "${expected_count}" ]]; then
    local actual_count
    actual_count=$(echo "${jf_output}" | jq '.totals.success')

    if [ "${actual_count}" -ne "${expected_count}" ]; then
      echoerr "❌ Expected ${expected_count} files for ${cmd_type}, but completed: ${actual_count}"
      echoerr "${jf_output}"
      exit 1
    fi
  fi
}
