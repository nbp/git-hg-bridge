#!/bin/sh

# This file only provides only utility functions and should be sourced.
# It provides a lightweight snapshot mechanism.  Multile options are possible to
# implement a snapshot mechanism (rsync, any union-fs, …), to prevent sources of
# failure this version is using rsync.

# :FIXME: Remove the hard-coded values.
SNAPSHOT_SOURCE=~git/source/
SNAPSHOT_POOL=~git/pool/
SNAPSHOT_ALLOC=~git/alloc/
SNAPSHOT_SYNC=~git/sync-lock

# Update an allocated snapshot.
_snapshot_update() {
  local dir="$1"

  ( flock -x 5
    if !rsync -ac "$SNAPSHOT_SOURCE" "$SNAPSHOT_ALLOC/$dir"; then
      rm -rf "$SNAPSHOT_ALLOC/$dir" || true
      rsync -ac "$SNAPSHOT_SOURCE" "$SNAPSHOT_ALLOC/$dir"
    fi
  ) 5> "$SNAPSHOT_SYNC"
}

# This is a private function used to create a new snapshot.
_snapshot_create() {
  # Knowing the process take more than a second and use only one snapshot, we
  # use the pid to prevent generating identical names.
  local dir="snap-$(date '+%s')-$$"
  mkdir "$SNAPSHOT_POOL/$dir"
}

snapshot_use() {
  # This is not work, but if it doesn't it will fail fast.
  test -z "$(cd "$SNAPSHOT_POOL"; ls *)" || \
    _snapshot_create

  # use ls to list the oldest snapshot first.
  for dir in $(cd "$SNAPSHOT_POOL"; ls *); do
    # Move will fail if another process has already allocated the dir.
    if mv "$SNAPSHOT_POOL/$dir" "$SNAPSHOT_ALLOC/$dir"; then
      _snapshot_update "$dir"
      echo "$dir"
      return 0
    fi
  done
  return 1;
}

snapshot_release() {
  local dir="$1"

  mkdir -p "$SNAPSHOT_POOL"
  mv "$SNAPSHOT_ALLOC/$dir" "$SNAPSHOT_POOL/."
}

snapshot_syncback() {
  local dir="$1"

  ( flock -x 5
    rsync -ac "$SNAPSHOT_ALLOC/$dir" "$SNAPSHOT_SOURCE"
  ) 5> "$SNAPSHOT_SYNC"
}

