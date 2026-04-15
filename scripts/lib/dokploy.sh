#!/usr/bin/env bash
set -euo pipefail

DOKPLOY_URL="${DOKPLOY_URL:-http://89.167.61.228:3000}"
DOKPLOY_API_BASE="${DOKPLOY_API_BASE:-${DOKPLOY_URL%/}/api}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_dokploy_api_key() {
  [[ -n "${DOKPLOY_API_KEY:-}" ]] || fail "DOKPLOY_API_KEY is required"
}

dokploy_request() {
  local method="${1:-}"
  local path="${2:-}"
  local body="${3:-}"

  [[ -n "$method" ]] || fail "dokploy_request: missing METHOD"
  [[ -n "$path" ]] || fail "dokploy_request: missing PATH"

  require_cmd curl
  require_dokploy_api_key

  if [[ "$path" != /* ]]; then
    path="/$path"
  fi

  local url="${DOKPLOY_API_BASE%/}${path}"
  local response_file
  response_file="$(mktemp)"
  local http_code

  if [[ "$method" == "GET" ]]; then
    http_code="$(curl -sS -X "$method" "$url" \
      -H "accept: application/json" \
      -H "x-api-key: $DOKPLOY_API_KEY" \
      -H "Authorization: Bearer $DOKPLOY_API_KEY" \
      -o "$response_file" \
      -w '%{http_code}')"
  else
    [[ -n "$body" ]] || body='{}'
    http_code="$(curl -sS -X "$method" "$url" \
      -H "accept: application/json" \
      -H "content-type: application/json" \
      -H "x-api-key: $DOKPLOY_API_KEY" \
      -H "Authorization: Bearer $DOKPLOY_API_KEY" \
      --data "$body" \
      -o "$response_file" \
      -w '%{http_code}')"
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "Dokploy API request failed" >&2
    echo "  method: $method" >&2
    echo "  url: $url" >&2
    echo "  status: $http_code" >&2
    echo "  body:" >&2
    sed -n '1,160p' "$response_file" >&2 || true
    rm -f "$response_file"
    return 1
  fi

  cat "$response_file"
  rm -f "$response_file"
}

bool_json() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|on|ON) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

slugify() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

classify_status() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$value" =~ ^(success|successful|ready|deployed|done|complete|completed)$ ]]; then
    printf '%s\n' "success"
    return 0
  fi
  if [[ "$value" =~ ^(error|failed|failure|cancelled|canceled|killed)$ ]]; then
    printf '%s\n' "failed"
    return 0
  fi
  if [[ "$value" =~ (running|building|queued|pending|preparing|starting|deploying|processing|in_progress)$ ]]; then
    printf '%s\n' "pending"
    return 0
  fi
  printf '%s\n' "unknown"
}
