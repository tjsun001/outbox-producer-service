#!/usr/bin/env bash
set -euo pipefail

############################################
# REQUIRED / DEFAULTED ENV
############################################
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-080967118593}"

ECR_REPO_NAME="${ECR_REPO_NAME:-outbox-producer-service}"
CONTAINER_NAME="${CONTAINER_NAME:-outbox-producer-service}"

CLUSTER_NAME="${CLUSTER_NAME:-mlops-poc-dev-ecs-cluster}"
SUBNET_A="${SUBNET_A:-subnet-09f6287483edd6c0d}"
SUBNET_B="${SUBNET_B:-subnet-061de6209161ca6a7}"
SECURITY_GROUP="${SECURITY_GROUP:-sg-0b2f59012ff85d984}"
ASSIGN_PUBLIC_IP="${ASSIGN_PUBLIC_IP:-DISABLED}"

TASKDEF_SMOKE_IN="${TASKDEF_SMOKE_IN:-ecs/task-definition.smoketest.json}"
LOG_GROUP="${LOG_GROUP:-/ecs/outbox-producer-service}"

# tag default: producer-<gitsha>
if git rev-parse --git-dir >/dev/null 2>&1; then
  DEFAULT_TAG="producer-$(git rev-parse --short HEAD)"
else
  DEFAULT_TAG="producer-manual"
fi
IMAGE_TAG="${IMAGE_TAG:-$DEFAULT_TAG}"

############################################
# DERIVED
############################################
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_REPO_URI="${ECR_REGISTRY}/${ECR_REPO_NAME}"
IMAGE_URI="${ECR_REPO_URI}:${IMAGE_TAG}"

############################################
# SANITY
############################################
command -v jq >/dev/null || { echo "ERROR: jq is required"; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker is required"; exit 1; }
test -f "$TASKDEF_SMOKE_IN" || { echo "ERROR: missing $TASKDEF_SMOKE_IN"; exit 1; }

echo "AWS_REGION=$AWS_REGION"
echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "ECR_REPO_NAME=$ECR_REPO_NAME"
echo "IMAGE_TAG=$IMAGE_TAG"
echo "IMAGE_URI=$IMAGE_URI"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "SUBNET_A=$SUBNET_A"
echo "SUBNET_B=$SUBNET_B"
echo "SECURITY_GROUP=$SECURITY_GROUP"
echo "TASKDEF_SMOKE_IN=$TASKDEF_SMOKE_IN"
echo "LOG_GROUP=$LOG_GROUP"
echo

############################################
# ECR LOGIN
############################################
aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1 || {
  echo "ERROR: ECR repo not found: $ECR_REPO_NAME"
  exit 1
}

aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

############################################
# BUILD + PUSH (amd64)
############################################
echo "==> Building and pushing linux/amd64..."
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE_URI" \
  --push \
  .

############################################
# RESOLVE DIGEST + PIN
############################################
echo "==> Resolving digest..."
IMAGE_DIGEST="$(
  aws ecr describe-images \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag="$IMAGE_TAG" \
    --query 'imageDetails[0].imageDigest' \
    --output text
)"

if [ -z "$IMAGE_DIGEST" ] || [ "$IMAGE_DIGEST" = "None" ]; then
  echo "ERROR: could not resolve digest for ${ECR_REPO_NAME}:${IMAGE_TAG}"
  exit 1
fi

IMAGE_URI_PINNED="${ECR_REPO_URI}@${IMAGE_DIGEST}"
echo "IMAGE_URI_PINNED=$IMAGE_URI_PINNED"
echo

############################################
# PATCH TASKDEF IMAGE (tmp file)
############################################
echo "==> Patching smoketest task definition image..."
TASKDEF_SMOKE_OUT="/tmp/taskdef.outbox-producer.smoketest.pinned.json"

jq --arg IMG "$IMAGE_URI_PINNED" --arg NAME "$CONTAINER_NAME" \
  '(.containerDefinitions[] | select(.name==$NAME) | .image) = $IMG' \
  "$TASKDEF_SMOKE_IN" > "$TASKDEF_SMOKE_OUT"

ACTUAL_IMAGE="$(jq -r --arg NAME "$CONTAINER_NAME" '.containerDefinitions[] | select(.name==$NAME) | .image' "$TASKDEF_SMOKE_OUT")"
if [ "$ACTUAL_IMAGE" != "$IMAGE_URI_PINNED" ]; then
  echo "ERROR: pinned image mismatch after patch"
  echo "EXPECTED=$IMAGE_URI_PINNED"
  echo "ACTUAL=$ACTUAL_IMAGE"
  exit 1
fi

echo "OK: patched $TASKDEF_SMOKE_OUT"
echo

############################################
# REGISTER TASKDEF
############################################
echo "==> Registering task definition..."
TD_ARN="$(
  aws ecs register-task-definition \
    --region "$AWS_REGION" \
    --cli-input-json "file://$TASKDEF_SMOKE_OUT" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text
)"
echo "TD_ARN=$TD_ARN"
echo

############################################
# RUN TASK
############################################
echo "==> Running smoketest task..."
TASK_ARN="$(
  aws ecs run-task \
    --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" \
    --launch-type FARGATE \
    --task-definition "$TD_ARN" \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_A,$SUBNET_B],securityGroups=[$SECURITY_GROUP],assignPublicIp=$ASSIGN_PUBLIC_IP}" \
    --query "tasks[0].taskArn" \
    --output text
)"
echo "TASK_ARN=$TASK_ARN"
echo

############################################
# WAIT FOR STOP
############################################
echo "==> Waiting for task to stop..."
aws ecs wait tasks-stopped \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --tasks "$TASK_ARN"

############################################
# VERIFY EXIT CODE
############################################
echo "==> Verifying exitCode..."
EXIT_CODE="$(
  aws ecs describe-tasks \
    --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --query "tasks[0].containers[?name=='${CONTAINER_NAME}'].exitCode | [0]" \
    --output text
)"
echo "EXIT_CODE=$EXIT_CODE"
if [ "$EXIT_CODE" != "0" ]; then
  echo "ERROR: smoketest failed (exitCode != 0)"
  exit 1
fi
echo

############################################
# FETCH + VERIFY LOGS
############################################
TASK_ID="${TASK_ARN##*/}"
LOG_STREAM="ecs/${CONTAINER_NAME}/${TASK_ID}"

echo "==> Fetching logs..."
echo "LOG_STREAM=$LOG_STREAM"
echo

# retry briefly for CW stream availability
for i in 1 2 3 4 5 6 7 8 9 10; do
  if aws logs get-log-events \
      --region "$AWS_REGION" \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name "$LOG_STREAM" \
      --limit 200 \
      --query "events[].message" \
      --output text > /tmp/producer-smoketest.log 2>/dev/null; then
    break
  fi
  sleep 2
done

tail -n 200 /tmp/producer-smoketest.log || true

echo
echo "==> Verifying success marker..."
if ! grep -q "DONE produced=1 exitCode=0" /tmp/producer-smoketest.log; then
  echo "ERROR: success marker not found in logs"
  exit 1
fi

echo "SUCCESS: Producer smoketest passed"