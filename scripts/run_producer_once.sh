#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:=us-east-1}"
: "${ECS_CLUSTER:=mlops-poc-dev-ecs-cluster}"
: "${TASK_DEFINITION_ARN:?Set TASK_DEFINITION_ARN (e.g., outbox-producer-service:123 or full ARN)}"
: "${CONTAINER_NAME:=outbox-producer-service}"

: "${SUBNET_A:=subnet-09f6287483edd6c0d}"
: "${SUBNET_B:=subnet-061de6209161ca6a7}"
: "${SECURITY_GROUP:=sg-0b2f59012ff85d984}"
: "${ASSIGN_PUBLIC_IP:=DISABLED}"

echo "Running producer task..."
echo

TASK_ARN="$(
  aws ecs run-task \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --launch-type FARGATE \
    --task-definition "$TASK_DEFINITION_ARN" \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A,$SUBNET_B],securityGroups=[$SECURITY_GROUP],assignPublicIp=$ASSIGN_PUBLIC_IP}" \
    --query "tasks[0].taskArn" \
    --output text
)"

echo "TASK_ARN=$TASK_ARN"

echo "Waiting for task to stop..."
aws ecs wait tasks-stopped \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --tasks "$TASK_ARN"

EXIT_CODE="$(
  aws ecs describe-tasks \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --tasks "$TASK_ARN" \
    --query "tasks[0].containers[?name=='$CONTAINER_NAME'].exitCode | [0]" \
    --output text
)"

echo "EXIT_CODE=$EXIT_CODE"

if [ "$EXIT_CODE" != "0" ]; then
  echo "Producer task failed."
  exit 1
fi

echo "Producer task completed successfully."