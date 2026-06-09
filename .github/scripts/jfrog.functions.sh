# distros and assets always come in fours
JF_CLI_THREAD_COUNT=4

function jfrog_cli_download_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  local cmd_type="${4:-download}"
  echo "${aql_payload}" | _execute_jf_command "${cmd_type}" "${expected_count}" $(_get_jf_options "aql" "${spec_vars}")
}

function jfrog_cli_download_by_file() {
  local target_dir="$1"
  local file_payload="$2"
  local expected_count="${3:-}"
  echo -n "" | _execute_jf_command "download" "${expected_count}" $(_get_jf_options "file" "") "${file_payload}" "${target_dir}/"
}

function jfrog_cli_copy_by_aql() {
  local aql_payload="$1"
  local spec_vars="$2"
  local expected_count="${3:-}"
  jfrog_cli_download_by_aql "${aql_payload}" "${spec_vars}" "${expected_count}" "copy"
}

function jfrog_cli_upload_by_file() {
  local target_repo_path="$1"
  local source_file_pattern="$2"
  local expected_count="${3:-}"
  echo -n "" | _execute_jf_command "upload" "${expected_count}" $(_get_jf_options "upload" "") "${source_file_pattern}" "${target_repo_path}/"
}

function jq_extract_json_aql() {
  local aql_json_string="$1"
  local target_key="$2"
  echo "${aql_json_string}" | jq --raw-output --arg target "${target_key}" '.[$target] | tostring'
}

function _get_jf_options() {
  local mode="$1"
  local spec_vars="${2:-}"
  local opts=()

  opts+=("--fail-no-op")
  opts+=("--format=json")
  opts+=("--threads" "${JF_CLI_THREAD_COUNT}")

  if [ "${mode}" = "aql" ]; then
    opts+=("--spec" "/dev/stdin")
    opts+=("--spec-vars=${spec_vars}")
  elif [ "${mode}" = "upload" ]; then
    opts+=("--flat")
  else
    opts+=("--build-name=false")
    opts+=("--build-number=false")
    opts+=("--flat")
    opts+=("--explode")
  fi

  echo "${opts[@]}"
}

function _execute_jf_command() {
  local cmd_type="$1"
  local expected_count="$2"
  shift 2

  source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

  local stdin_payload
  stdin_payload=$(cat)

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
