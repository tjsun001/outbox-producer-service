#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:=us-east-1}"
: "${AWS_ACCOUNT_ID:?set AWS_ACCOUNT_ID}"
: "${ECR_REPO_NAME:=outbox-producer-service}"
: "${IMAGE_TAG:=producer-$(git rev-parse --short HEAD)}"

ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO_NAME" >/dev/null

aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker buildx build \
  --platform linux/amd64 \
  -t "${ECR_REPO_URI}:${IMAGE_TAG}" \
  --push \
  .

DIGEST="$(aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "$ECR_REPO_NAME" \
  --image-ids imageTag="$IMAGE_TAG" \
  --query 'imageDetails[0].imageDigest' \
  --output text)"

echo "IMAGE_TAG=$IMAGE_TAG"
echo "IMAGE_DIGEST=$DIGEST"
echo "IMAGE_URI_PINNED=${ECR_REPO_URI}@${DIGEST}"