#!/usr/bin/env bash
# Send a prompt to a running OpenCode server and let it drive the SEM.
# Usage: scripts/opencode-sem.sh "set a diatom frustule in the SEM"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/scripts/opencode.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
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
else
  unset OPENCODE_PASSWORD
  unset OPENCODE_SERVER_PASSWORD
fi

PROMPT="${*:-Use the sem_set_sample tool to set a pollen grain with spiky exine in the SEM.}"
AGENT="${OPENCODE_AGENT:-build}"

ARGS=(run --server "$URL" --auto --agent "$AGENT")
if [[ -n "${OPENCODE_MODEL:-}" ]]; then
  ARGS+=(--model "$OPENCODE_MODEL")
fi

exec opencode "${ARGS[@]}" "$PROMPT"
