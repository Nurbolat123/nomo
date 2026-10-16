#!/usr/bin/env bash
# Runs a command; on failure reports its last lines as a GitHub annotation
# (readable through the checks API even when raw logs are not).
#   tool/ci_run.sh "title" cmd args...
title="$1"; shift
out=$(mktemp)
"$@" 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  msg=$(grep -vE '^\s*$' "$out" | tail -n 60 | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  echo "::error title=${title}::${msg}"
fi
exit "$code"
