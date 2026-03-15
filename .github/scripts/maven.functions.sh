source /dev/stdin <<< "$(curl --silent https://raw.githubusercontent.com/hazelcast/github-actions-common-scripts/main/logging.functions.sh)"

# Returns a path to a given Maven artifact, downloading if required
# https://maven.apache.org/plugins/maven-dependency-plugin/get-mojo.html
function get_maven_artifact() {
    local group_id=$1
    local artifact_id=$2
    local artifact_version=$3
    local remote_repositories=$4

    # Download the dependency
    # Overrides any existing "MAVEN_OPTS" environment configuration
    #
    # This is to ignore any custom configuration of the parent Maven invocation that will interfere with this simple query
    #
    # https://github.com/hazelcast/hazelcast/issues/25451#issuecomment-1720248676/
    MAVEN_OPTS="" \
    MAVEN_ARGS="--batch-mode --quiet" \
    ./mvnw dependency:get \
        -DgroupId="${group_id}" \
        -DartifactId="${artifact_id}" \
        -Dversion="${artifact_version}" \
        -DremoteRepositories="${remote_repositories}"

    repo_path=$(get_repo_path)

    if [[ -d "${repo_path}" ]]; then
        artifact_path="${repo_path}/${group_id//.//}/${artifact_id}/${artifact_version}/${artifact_id}-${artifact_version}.jar"

        if [[ -f "${artifact_path}" ]]; then
            echo "${artifact_path}"
        else
            exit_with_error "${group_id}:${artifact_id} not found at ${repo_path}!"
        fi
    else
        exit_with_error "Maven repository not found in ${repo_path}!"
    fi
}

# Query Maven for the path to the local Maven repository (typically ~/.m2/repository)
function get_repo_path() {
    # shellcheck disable=SC2068
    evaluate_mvn_expression "settings.localRepository" ${@-}
}

function get_project_version() {
    # shellcheck disable=SC2068
    evaluate_mvn_expression "project.version" ${@-}
}

function evaluate_mvn_expression() {
    local expression=$1

    shift 1

    # Overrides any existing "MAVEN_OPTS" environment configuration
    #
    # This is to ignore any custom configuration of the parent Maven invocation that will interfere with this simple query
    #
    # https://github.com/hazelcast/hazelcast/issues/25451#issuecomment-1720248676/
    MAVEN_OPTS="" \
    MAVEN_ARGS="--batch-mode --quiet" \
    ./mvnw \
        help:evaluate \
        -Dexpression="${expression}" \
        -DforceStdout \
        --raw-streams \
        "$@"
}

# Returns common Maven arguments all executions should use, ready to set in MAVEN_ARGS variable
# https://maven.apache.org/configure.html#maven_args-environment-variable
function get_maven_args() {
    local maven_args=()
    maven_args+=(--batch-mode)
    maven_args+=(--errors)
    maven_args+=(--no-transfer-progress)
    maven_args+=(-Dmaven.compiler.useIncrementalCompilation=false)

    # Add Build Time args
    # Allows profiling of build execution time
    # https://hazelcast.slack.com/archives/C01JU7ZJYGP/p1709147490425909
    maven_args+=(-Dbuildtime.output.gantt=true)
    maven_args+=(-Dbuildtime.output.log=true)
    # Can't be in `.mvn/extensions.xml` as doesn't support custom repositories
    maven_gantt_extension_path=$(get_maven_artifact co.leantechniques maven-gantt-extension 1.0.0 https://repository.hazelcast.com/release)
    maven_args+=(-Dmaven.ext.class.path="${maven_gantt_extension_path}")
 
    # shellcheck disable=SC2310
    if is_debug; then
        maven_args+=(--show-version)
    fi

    echo "${maven_args[*]}"
}

# Query if GitHub Action's debug logging is enabled
# https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/enabling-debug-logging
function is_debug() {
    if [[ "${RUNNER_DEBUG-0}" = 1 ]]; then
        true
    else
        false
    fi
}

function exit_with_error() {
    local message=$1

    echoerr "ERROR: ${message}"
    exit 1
}

# shellcheck disable=SC2310
if is_debug; then
    set -o xtrace
fi
