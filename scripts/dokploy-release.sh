#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/dokploy.sh"

require_cmd jq
require_dokploy_api_key

PROJECT_NAME="${PROJECT_NAME:-euphoria-season-3}"
PROJECT_DESCRIPTION="${PROJECT_DESCRIPTION:-Static keyword landing page for Euphoria Season 3}"
APPLICATION_NAME="${APPLICATION_NAME:-euphoria-season-3}"
APP_NAME="${APP_NAME:-$(slugify "$APPLICATION_NAME")}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
PRIMARY_URL="${PRIMARY_URL:-https://euphoria-season-3.lol}"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-euphoria-season-3.lol}"
WWW_DOMAIN="${WWW_DOMAIN:-www.euphoria-season-3.lol}"
GITHUB_OWNER="${GITHUB_OWNER:-gateszhangc}"
GITHUB_REPO="${GITHUB_REPO:-euphoria-season-3}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_BUILD_PATH="${GIT_BUILD_PATH:-.}"
AUTO_DEPLOY="${AUTO_DEPLOY:-true}"
ENABLE_SUBMODULES="${ENABLE_SUBMODULES:-false}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-Dockerfile}"
DOCKER_CONTEXT_PATH="${DOCKER_CONTEXT_PATH:-.}"
DOCKER_BUILD_STAGE="${DOCKER_BUILD_STAGE:-}"
TARGET_PORT="${TARGET_PORT:-80}"
PUBLISHED_PORT="${PUBLISHED_PORT:-}"
DEPLOY_WAIT_SECONDS="${DEPLOY_WAIT_SECONDS:-900}"
DEPLOY_POLL_INTERVAL_SECONDS="${DEPLOY_POLL_INTERVAL_SECONDS:-5}"
PREFERRED_SERVER_IP="${PREFERRED_SERVER_IP:-89.167.61.228}"
ENV_FILE="${ENV_FILE:-.env.production}"

find_project_id() {
  local project_name="$1"
  dokploy_request GET /project.all | jq -r --arg name "$project_name" 'first(.[] | select(.name == $name) | .projectId) // empty'
}

find_environment_id() {
  local project_id="$1"
  dokploy_request GET "/project.one?projectId=$project_id" |
    jq -r --arg name "$ENVIRONMENT_NAME" 'first(.environments[]? | select(.name == $name) | .environmentId) // first(.environments[]?.environmentId) // empty'
}

find_application_id() {
  local project_id="$1"
  dokploy_request GET "/project.one?projectId=$project_id" |
    jq -r --arg name "$APPLICATION_NAME" 'first(.environments[]?.applications[]? | select(.name == $name) | .applicationId) // empty'
}

create_project() {
  local payload
  payload="$(jq -cn --arg name "$PROJECT_NAME" --arg description "$PROJECT_DESCRIPTION" '{name: $name, description: $description}')"
  dokploy_request POST /project.create "$payload" >/dev/null
}

select_server_id() {
  local server_type="$1"
  dokploy_request GET /server.all |
    jq -r --arg type "$server_type" --arg ip "$PREFERRED_SERVER_IP" '
      first(.[] | select(.serverType == $type and .serverStatus == "active" and .ipAddress == $ip) | .serverId)
      // first(.[] | select(.serverType == $type and .serverStatus == "active") | .serverId)
      // empty
    '
}

pick_free_published_port() {
  local used
  used="$(dokploy_request GET /project.all | jq -r '[.[]?.environments[]?.applications[]?.ports[]?.publishedPort] | map(select(. != null)) | unique | .[]?')"
  local port
  for port in $(seq 14080 14160); do
    if ! grep -qx "$port" <<<"$used"; then
      printf '%s\n' "$port"
      return 0
    fi
  done
  fail "unable to find a free published port in 14080-14160"
}

create_application() {
  local environment_id="$1"
  local server_id="$2"
  local payload
  payload="$(jq -cn \
    --arg name "$APPLICATION_NAME" \
    --arg appName "$APP_NAME" \
    --arg environmentId "$environment_id" \
    --arg serverId "$server_id" \
    '{name: $name, appName: $appName, environmentId: $environmentId, serverId: $serverId}')"
  dokploy_request POST /application.create "$payload" >/dev/null
}

configure_build() {
  local application_id="$1"
  local payload
  payload="$(jq -cn \
    --arg applicationId "$application_id" \
    --arg buildType "dockerfile" \
    --arg dockerfile "$DOCKERFILE_PATH" \
    --arg dockerContextPath "$DOCKER_CONTEXT_PATH" \
    --arg dockerBuildStage "$DOCKER_BUILD_STAGE" \
    '{
      applicationId: $applicationId,
      buildType: $buildType,
      dockerfile: $dockerfile,
      dockerContextPath: $dockerContextPath,
      dockerBuildStage: $dockerBuildStage,
      herokuVersion: null,
      railpackVersion: null
    }')"
  dokploy_request POST /application.saveBuildType "$payload" >/dev/null
}

configure_git() {
  local application_id="$1"
  local git_url="$2"
  local enable_submodules
  enable_submodules="$(bool_json "$ENABLE_SUBMODULES")"
  local payload
  payload="$(jq -cn \
    --arg applicationId "$application_id" \
    --arg customGitUrl "$git_url" \
    --arg customGitBranch "$GIT_BRANCH" \
    --arg customGitBuildPath "$GIT_BUILD_PATH" \
    --argjson enableSubmodules "$enable_submodules" \
    '{
      applicationId: $applicationId,
      customGitUrl: $customGitUrl,
      customGitBranch: $customGitBranch,
      customGitBuildPath: $customGitBuildPath,
      watchPaths: [],
      enableSubmodules: $enableSubmodules
    }')"
  dokploy_request POST /application.saveGitProvider "$payload" >/dev/null
}

configure_auto_deploy() {
  local application_id="$1"
  local build_server_id="$2"
  local auto_deploy
  auto_deploy="$(bool_json "$AUTO_DEPLOY")"
  local payload
  payload="$(jq -cn \
    --arg applicationId "$application_id" \
    --arg buildServerId "$build_server_id" \
    --arg sourceType "git" \
    --argjson autoDeploy "$auto_deploy" \
    '{
      applicationId: $applicationId,
      sourceType: $sourceType,
      autoDeploy: $autoDeploy,
      buildServerId: $buildServerId
    }')"
  dokploy_request POST /application.update "$payload" >/dev/null
}

configure_port() {
  local application_id="$1"
  local published_port="$2"
  local app_json existing_port_id payload
  app_json="$(dokploy_request GET "/application.one?applicationId=$application_id")"
  existing_port_id="$(jq -r 'first([.ports[]?.portId][]) // empty' <<<"$app_json")"

  if [[ -n "$existing_port_id" ]]; then
    payload="$(jq -cn \
      --arg portId "$existing_port_id" \
      --argjson publishedPort "$published_port" \
      --argjson targetPort "$TARGET_PORT" \
      --arg publishMode "ingress" \
      --arg protocol "tcp" \
      '{portId: $portId, publishedPort: $publishedPort, targetPort: $targetPort, publishMode: $publishMode, protocol: $protocol}')"
    dokploy_request POST /port.update "$payload" >/dev/null
  else
    payload="$(jq -cn \
      --arg applicationId "$application_id" \
      --argjson publishedPort "$published_port" \
      --argjson targetPort "$TARGET_PORT" \
      --arg publishMode "ingress" \
      --arg protocol "tcp" \
      '{applicationId: $applicationId, publishedPort: $publishedPort, targetPort: $targetPort, publishMode: $publishMode, protocol: $protocol}')"
    dokploy_request POST /port.create "$payload" >/dev/null
  fi
}

ensure_domain() {
  local application_id="$1"
  local host="$2"
  local app_json domain_id payload

  app_json="$(dokploy_request GET "/application.one?applicationId=$application_id")"
  domain_id="$(jq -r --arg host "$host" 'first([.domains[]? | select(.host == $host) | .domainId][]) // empty' <<<"$app_json")"
  if [[ -n "$domain_id" ]]; then
    return 0
  fi

  payload="$(jq -cn \
    --arg host "$host" \
    --arg applicationId "$application_id" \
    --arg certificateType "letsencrypt" \
    '{host: $host, applicationId: $applicationId, https: true, certificateType: $certificateType, domainType: "application"}')"
  dokploy_request POST /domain.create "$payload" >/dev/null
}

sync_environment() {
  local application_id="$1"
  [[ -f "$ROOT_DIR/$ENV_FILE" ]] || return 0
  local env_string payload
  env_string="$(cat "$ROOT_DIR/$ENV_FILE")"
  payload="$(jq -cn \
    --arg applicationId "$application_id" \
    --arg env "$env_string" \
    '{applicationId: $applicationId, env: $env, buildArgs: null, buildSecrets: null, createEnvFile: true}')"
  dokploy_request POST /application.saveEnvironment "$payload" >/dev/null
}

trigger_deployment() {
  local application_id="$1"
  local payload
  payload="$(jq -cn --arg applicationId "$application_id" '{applicationId: $applicationId}')"
  dokploy_request POST /application.deploy "$payload" >/dev/null
}

wait_for_deployment() {
  local application_id="$1"
  local started_at latest_json latest_id latest_status phase latest_error
  started_at="$(date +%s)"

  while true; do
    latest_json="$(dokploy_request GET "/deployment.all?applicationId=$application_id" | jq -c '([.. | objects | select(.deploymentId? != null)] | sort_by(.createdAt // .created_at // "") | last) // empty')"
    latest_id="$(jq -r '.deploymentId // empty' <<<"$latest_json")"
    latest_status="$(jq -r '(.status // .state // .deploymentStatus // .result // empty) // empty' <<<"$latest_json")"
    latest_error="$(jq -r '.errorMessage // empty' <<<"$latest_json")"
    phase="$(classify_status "$latest_status")"

    if [[ "$phase" == "success" ]]; then
      printf 'deploymentId=%s\n' "$latest_id"
      printf 'deploymentStatus=%s\n' "$latest_status"
      return 0
    fi

    if [[ "$phase" == "failed" ]]; then
      fail "Dokploy deployment failed (deploymentId=${latest_id:-n/a}, status=${latest_status:-unknown}, error=${latest_error:-n/a})"
    fi

    if (( $(date +%s) - started_at >= DEPLOY_WAIT_SECONDS )); then
      fail "timed out waiting for Dokploy deployment (deploymentId=${latest_id:-n/a}, status=${latest_status:-unknown})"
    fi

    sleep "$DEPLOY_POLL_INTERVAL_SECONDS"
  done
}

PROJECT_ID="$(find_project_id "$PROJECT_NAME")"
if [[ -z "$PROJECT_ID" ]]; then
  create_project
  PROJECT_ID="$(find_project_id "$PROJECT_NAME")"
fi
[[ -n "$PROJECT_ID" ]] || fail "unable to resolve Dokploy projectId for $PROJECT_NAME"

ENVIRONMENT_ID="$(find_environment_id "$PROJECT_ID")"
[[ -n "$ENVIRONMENT_ID" ]] || fail "unable to resolve Dokploy environmentId for $PROJECT_NAME"

APPLICATION_ID="$(find_application_id "$PROJECT_ID")"
DEPLOY_SERVER_ID="$(select_server_id deploy)"
BUILD_SERVER_ID="$(select_server_id build)"
[[ -n "$DEPLOY_SERVER_ID" ]] || fail "unable to resolve deploy server"
[[ -n "$BUILD_SERVER_ID" ]] || fail "unable to resolve build server"

if [[ -z "$APPLICATION_ID" ]]; then
  create_application "$ENVIRONMENT_ID" "$DEPLOY_SERVER_ID"
  APPLICATION_ID="$(find_application_id "$PROJECT_ID")"
fi
[[ -n "$APPLICATION_ID" ]] || fail "unable to resolve Dokploy applicationId for $APPLICATION_NAME"

GIT_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO.git"
if [[ -z "$PUBLISHED_PORT" ]]; then
  PUBLISHED_PORT="$(pick_free_published_port)"
fi

configure_build "$APPLICATION_ID"
configure_git "$APPLICATION_ID" "$GIT_URL"
configure_auto_deploy "$APPLICATION_ID" "$BUILD_SERVER_ID"
configure_port "$APPLICATION_ID" "$PUBLISHED_PORT"
ensure_domain "$APPLICATION_ID" "$PRIMARY_DOMAIN"
ensure_domain "$APPLICATION_ID" "$WWW_DOMAIN"
sync_environment "$APPLICATION_ID"
trigger_deployment "$APPLICATION_ID"
wait_for_deployment "$APPLICATION_ID"

printf 'projectId=%s\n' "$PROJECT_ID"
printf 'environmentId=%s\n' "$ENVIRONMENT_ID"
printf 'applicationId=%s\n' "$APPLICATION_ID"
printf 'deployServerId=%s\n' "$DEPLOY_SERVER_ID"
printf 'buildServerId=%s\n' "$BUILD_SERVER_ID"
printf 'primaryUrl=%s\n' "$PRIMARY_URL"
printf 'gitUrl=%s\n' "$GIT_URL"
