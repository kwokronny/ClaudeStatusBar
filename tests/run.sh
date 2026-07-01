#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
for t in "$DIR"/test_*.sh; do
  echo "== $t"
  bash "$t"
done
echo "ALL TESTS PASSED"
