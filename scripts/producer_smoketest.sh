#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-poc-dev-ecs-cluster}"
TASKDEF_PATH="${TASKDEF_PATH:-ecs/task-definition.smoketest.json}"
CONTAINER_NAME="outbox-producer-service"
LOG_GROUP="/ecs/outbox-producer-service"

SUBNETS="subnet-09f6287483edd6c0d,subnet-061de6209161ca6a7"
SECURITY_GROUP="sg-0b2f59012ff85d984"

############################################
# REGISTER TASK DEF
############################################

echo "Registering smoketest task definition..."

TD_ARN=$(
  aws ecs register-task-definition \
    --region "$AWS_REGION" \
    --cli-input-json "file://$TASKDEF_PATH" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text
)

echo "TD_ARN=$TD_ARN"

############################################
# RUN TASK
############################################

echo "Running smoketest task..."

TASK_ARN=$(
  aws ecs run-task \
    --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" \
    --launch-type FARGATE \
    --task-definition "$TD_ARN" \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
    --query "tasks[0].taskArn" \
    --output text
)

echo "TASK_ARN=$TASK_ARN"

TASK_ID="${TASK_ARN##*/}"
LOG_STREAM="ecs/${CONTAINER_NAME}/${TASK_ID}"

############################################
# WAIT FOR LOG STREAM
############################################

echo "Waiting for log stream..."

for i in {1..20}; do
  if aws logs describe-log-streams \
      --region "$AWS_REGION" \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name-prefix "$LOG_STREAM" \
      --query "logStreams[0].logStreamName" \
      --output text 2>/dev/null | grep -q "$TASK_ID"; then
    break
  fi
  sleep 2
done

############################################
# FETCH LOGS
############################################

echo
echo "===== PRODUCER SMOKETEST LOGS ====="

aws logs get-log-events \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$LOG_STREAM" \
  --limit 200 \
  --query "events[].message" \
  --output text

echo "==================================="
echo

############################################
# VERIFY SUCCESS MARKER
############################################

if aws logs get-log-events \
    --region "$AWS_REGION" \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LOG_STREAM" \
    --limit 200 \
    --query "events[].message" \
    --output text | grep -q "DONE produced=1 exitCode=0"
then
  echo "SUCCESS: Producer smoketest passed"
else
  echo "ERROR: Producer smoketest failed"
  exit 1
fi