#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-poc-dev-msk-serverless}"
TOPIC_NAME="${TOPIC_NAME:-outbox.events.test}"
OUTPUT_DIR="${OUTPUT_DIR:-infra/msk-baseline}"

mkdir -p "$OUTPUT_DIR"

echo "==> Capturing caller identity"
aws sts get-caller-identity --output json > "$OUTPUT_DIR/caller-identity.json"

echo "==> Resolving Serverless cluster ARN by name: $CLUSTER_NAME"
CLUSTER_ARN="$(
  aws kafka list-clusters-v2 \
    --region "$AWS_REGION" \
    --query "ClusterInfoList[?ClusterType=='SERVERLESS' && ClusterName=='${CLUSTER_NAME}'].ClusterArn | [0]" \
    --output text
)"
[[ -n "$CLUSTER_ARN" && "$CLUSTER_ARN" != "None" ]] || { echo "ERROR: cluster not found"; exit 1; }
echo "    CLUSTER_ARN=$CLUSTER_ARN"
echo "$CLUSTER_ARN" > "$OUTPUT_DIR/cluster-arn.txt"

echo "==> Describing cluster"
aws kafka describe-cluster-v2 \
  --region "$AWS_REGION" \
  --cluster-arn "$CLUSTER_ARN" \
  --output json \
  > "$OUTPUT_DIR/msk-cluster.json"
echo "    describe-cluster-v2 succeeded."

echo "==> Capturing bootstrap brokers"
aws kafka get-bootstrap-brokers \
  --region "$AWS_REGION" \
  --cluster-arn "$CLUSTER_ARN" \
  --output json \
  > "$OUTPUT_DIR/bootstrap-brokers.json"

# Extract bootstrap safely using jq only
BOOTSTRAP_SERVERS="$(
  jq -r '
    .BootstrapBrokerStringSaslIam //
    .BootstrapBrokerStringTls //
    .BootstrapBrokerStringPublicSaslIam //
    .BootstrapBrokerStringPublicTls //
    .BootstrapBrokerString //
    empty
  ' "$OUTPUT_DIR/bootstrap-brokers.json"
)"
[[ -n "$BOOTSTRAP_SERVERS" ]] || { echo "ERROR: could not extract bootstrap servers"; exit 1; }

echo "$BOOTSTRAP_SERVERS" > "$OUTPUT_DIR/bootstrap-servers.txt"
echo "    BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS"

echo "==> Writing topic baseline"
cat > "$OUTPUT_DIR/topic-config.json" <<EOF
{
  "clusterName": "$CLUSTER_NAME",
  "clusterArn": "$CLUSTER_ARN",
  "region": "$AWS_REGION",
  "topic": "$TOPIC_NAME",
  "auth": "IAM",
  "clusterType": "MSK_SERVERLESS"
}
EOF

echo "==> Writing ECS env baseline"
cat > "$OUTPUT_DIR/producer-env-baseline.env" <<EOF
AWS_REGION=$AWS_REGION
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_ARN=$CLUSTER_ARN
SPRING_PROFILES_ACTIVE=aws
SPRING_KAFKA_BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS
APP_TOPIC=$TOPIC_NAME
EOF

echo
echo "========================"
echo "BASELINE CAPTURE COMPLETE"
echo "========================"
echo "Output directory: $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -print | sed 's/^/ - /'
