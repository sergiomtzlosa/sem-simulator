#!/usr/bin/env bash
# Start the OpenCode V2 API/web server. Authentication is optional: a missing or
# empty password file starts the server without a password.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/scripts/opencode.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
PORT="${OPENCODE_PORT:-4096}"
PASSWORD_FILE="${OPENCODE_PASSWORD_FILE:-.opencode/password}"
if [[ "$PASSWORD_FILE" != /* ]]; then
  PASSWORD_FILE="$ROOT/$PASSWORD_FILE"
fi

PASSWORD=""
if [[ -r "$PASSWORD_FILE" ]]; then
  PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
fi

if [[ -n "$PASSWORD" ]]; then
  export OPENCODE_PASSWORD="$PASSWORD"
  export OPENCODE_SERVER_PASSWORD="$PASSWORD"
  echo "OpenCode authentication enabled from $PASSWORD_FILE" >&2
else
  unset OPENCODE_PASSWORD
  unset OPENCODE_SERVER_PASSWORD
  echo "OpenCode authentication disabled (empty or missing password file: $PASSWORD_FILE)" >&2
fi

cd "$ROOT"
exec opencode serve --hostname "$HOSTNAME" --port "$PORT" "$@"
