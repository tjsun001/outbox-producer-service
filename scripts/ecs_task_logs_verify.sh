#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:=us-east-1}"
: "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${TASK_ARN:?set TASK_ARN}"
: "${LOG_GROUP:?set LOG_GROUP}"
: "${CONTAINER_NAME:=outbox-producer-service}"

TASK_ID="${TASK_ARN##*/}"
LOG_STREAM="ecs/${CONTAINER_NAME}/${TASK_ID}"

echo "TASK_ARN=$TASK_ARN"
echo "LOG_GROUP=$LOG_GROUP"
echo "LOG_STREAM=$LOG_STREAM"

# Pull logs (retry briefly in case CW stream is slightly delayed)
for i in 1 2 3 4 5 6 7 8 9 10; do
  if AWS_PAGER="" aws logs get-log-events \
      --region "$AWS_REGION" \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name "$LOG_STREAM" \
      --limit 200 \
      --query "events[].message" \
      --output text > /tmp/task.log 2>/dev/null; then
    break
  fi
  sleep 2
done

echo "---- last 80 lines ----"
tail -n 80 /tmp/task.log || true
echo "-----------------------"

# Assert success marker exists
if ! grep -q "DONE produced=1 exitCode=0" /tmp/task.log; then
  echo "ERROR: success marker not found in logs"
  exit 1
fi

# Assert task exitCode=0
EXIT_CODE="$(AWS_PAGER="" aws ecs describe-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --tasks "$TASK_ARN" \
  --query "tasks[0].containers[?name=='${CONTAINER_NAME}'].exitCode | [0]" \
  --output text)"

echo "EXIT_CODE=$EXIT_CODE"
test "$EXIT_CODE" = "0"
echo "OK: smoketest succeeded"