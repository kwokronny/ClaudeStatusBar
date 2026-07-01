#!/usr/bin/env bash
assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: expected [$2] got [$1]" >&2
    exit 1
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle>
  case "$1" in
    *"$2"*) : ;;
    *) echo "FAIL: [$1] does not contain [$2]" >&2; exit 1 ;;
  esac
}
