#!/bin/sh
# Simple health check script for the deployed backend
# Usage: ./health_check.sh <PUBLIC_IP> [PORT]
# Default PORT is 8000

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <PUBLIC_IP> [PORT]" 1>&2
  exit 2
fi

IP="$1"
PORT="${2:-8000}"

BASE="http://$IP:$PORT"

printf "Checking %s/health...\n" "$BASE"
if ! curl -fsS "$BASE/health" > /dev/null; then
  echo "Health check failed" 1>&2
  exit 1
fi

printf "Checking %s/ready...\n" "$BASE"
if ! curl -fsS "$BASE/ready" > /dev/null; then
  echo "Readiness check failed" 1>&2
  exit 1
fi

printf "OK. Open docs: %s/docs\n" "$BASE"
