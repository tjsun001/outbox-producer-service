#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:=us-east-1}"
: "${AWS_ACCOUNT_ID:?set AWS_ACCOUNT_ID}"

# cluster + network (your known-good values)
: "${CLUSTER_NAME:=mlops-poc-dev-ecs-cluster}"
: "${SUBNET_A:=subnet-09f6287483edd6c0d}"
: "${SUBNET_B:=subnet-061de6209161ca6a7}"
: "${SECURITY_GROUP:=sg-0b2f59012ff85d984}"

export ECR_REPO_NAME="${ECR_REPO_NAME:-outbox-producer-service}"
export IMAGE_TAG="${IMAGE_TAG:-producer-$(git rev-parse --short HEAD)}"

# 1) build/push and capture pinned uri
PINNED_LINE="$(./scripts/producer_build_push.sh | tee /dev/stderr | grep '^IMAGE_URI_PINNED=')"
export IMAGE_URI_PINNED="${PINNED_LINE#IMAGE_URI_PINNED=}"

# 2) patch smoketest taskdef image
export TASKDEF_IN="ecs/task-definition.smoketest.json"
export TASKDEF_OUT="/tmp/taskdef.producer.smoketest.pinned.json"
./scripts/patch_taskdef_image.sh

# 3) register
TD_ARN="$(aws ecs register-task-definition \
  --region "$AWS_REGION" \
  --cli-input-json "file://$TASKDEF_OUT" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)"
echo "TD_ARN=$TD_ARN"

# 4) run
TASK_ARN="$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --launch-type FARGATE \
  --task-definition "$TD_ARN" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A,$SUBNET_B],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --query "tasks[0].taskArn" \
  --output text)"
echo "TASK_ARN=$TASK_ARN"

# 5) verify logs + DONE marker + exitCode (reuse the earlier verifier idea)
export LOG_GROUP="/ecs/outbox-producer-service"
export CONTAINER_NAME="outbox-producer-service"
export TASK_ARN
./scripts/ecs_task_logs_verify.sh