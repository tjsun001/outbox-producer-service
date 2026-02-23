#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   AWS_REGION=us-east-1 ACCOUNT_ID=080967118593 REPO=outbox-producer-service TAG=sha-xxxx ./scripts/ecr_build_push.sh

: "${AWS_REGION:=us-east-1}"
: "${ACCOUNT_ID:?set ACCOUNT_ID}"
: "${REPO:?set REPO}"
: "${TAG:?set TAG}"

IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO}:${TAG}"

echo "IMAGE_URI=$IMAGE_URI"

# Ensure we have a buildx builder
if ! docker buildx inspect mlops-builder >/dev/null 2>&1; then
  docker buildx create --name mlops-builder --use >/dev/null
else
  docker buildx use mlops-builder >/dev/null
fi

# Ensure QEMU is installed for cross-building (safe to run repeatedly)
docker run --privileged --rm tonistiigi/binfmt --install amd64 >/dev/null 2>&1 || true

# ECR login (token refresh)
aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin \
  "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" >/dev/null

# Build + push ALWAYS as linux/amd64
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE_URI" \
  --push \
  .

echo "Pushed: $IMAGE_URI"