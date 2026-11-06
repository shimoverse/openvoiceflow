#!/usr/bin/env bash
# Retry only stapler's observed transient CloudKit connection-loss failure.
# Every operation remains blocking; retries are independent per staple/validate.
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != staple && "$1" != validate ) || -z "$2" ]]; then
  echo "usage: $0 {staple|validate} artifact" >&2
  exit 2
fi

for attempt in 1 2 3; do
  if output=$(xcrun stapler "$1" "$2" 2>&1); then
    printf '%s\n' "$output"
    exit 0
  else
    status=$?
  fi
  printf '%s\n' "$output" >&2
  if [[ $status -ne 68 || "$output" != *'NSURLErrorDomain Code=-1005'* || $attempt -eq 3 ]]; then
    exit "$status"
  fi
  echo "::warning::stapler $1 lost connection; retrying ($attempt/3)" >&2
  sleep "$attempt"  # 1s, then 2s; at most three total attempts.
done
