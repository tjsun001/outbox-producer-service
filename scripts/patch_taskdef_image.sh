#!/usr/bin/env bash
set -euo pipefail

: "${TASKDEF_IN:?set TASKDEF_IN}"
: "${TASKDEF_OUT:?set TASKDEF_OUT}"
: "${CONTAINER_NAME:=outbox-producer-service}"
: "${IMAGE_URI_PINNED:?set IMAGE_URI_PINNED}"

jq --arg IMG "$IMAGE_URI_PINNED" --arg NAME "$CONTAINER_NAME" \
  '(.containerDefinitions[] | select(.name==$NAME) | .image) = $IMG' \
  "$TASKDEF_IN" > "$TASKDEF_OUT"

echo "Patched image in $TASKDEF_OUT:"
jq -r --arg NAME "$CONTAINER_NAME" \
  '.containerDefinitions[] | select(.name==$NAME) | .image' \
  "$TASKDEF_OUT"