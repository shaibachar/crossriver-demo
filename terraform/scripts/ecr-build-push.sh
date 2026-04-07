#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# ecr-build-push.sh
#
# Builds all six microservice Docker images and pushes them to their respective
# ECR repositories.
#
# Usage:
#   ./terraform/scripts/ecr-build-push.sh [project] [environment] [region]
#
# Defaults:
#   project     = crossriver
#   environment = prod
#   region      = us-east-1
#
# Prerequisites:
#   - Docker running
#   - AWS CLI v2 configured with permissions to push to ECR
#   - Run from the repository root (where CrossRiverDemo.sln lives)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT="${1:-crossriver}"
ENV="${2:-prod}"
REGION="${3:-${AWS_DEFAULT_REGION:-us-east-1}}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
PREFIX="${PROJECT}-${ENV}"

echo "=> Logging in to ECR (${ECR_BASE})"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${ECR_BASE}"

# Map service name → Dockerfile path (relative to repo root)
declare -A DOCKERFILES
DOCKERFILES["simulation-api"]="src/Simulation.Api/Dockerfile"
DOCKERFILES["crossriver-adapter"]="src/CrossRiver.Adapter/Dockerfile"
DOCKERFILES["projection-engine"]="src/Projection.Engine/Dockerfile"
DOCKERFILES["execution-service"]="src/Execution.Service/Dockerfile"
DOCKERFILES["webhook-ingest"]="src/Webhook.Ingest/Dockerfile"
DOCKERFILES["audit-comparison"]="src/Audit.Comparison/Dockerfile"

for SERVICE in "${!DOCKERFILES[@]}"; do
  DOCKERFILE="${DOCKERFILES[$SERVICE]}"
  IMAGE="${ECR_BASE}/${PREFIX}/${SERVICE}:latest"

  echo ""
  echo "=> Building ${SERVICE} from ${DOCKERFILE}"
  docker build \
    --file "${DOCKERFILE}" \
    --tag  "${IMAGE}" \
    .

  echo "=> Pushing ${IMAGE}"
  docker push "${IMAGE}"
done

echo ""
echo "All images pushed successfully."
echo "Run 'terraform apply' (or update ECS services) to deploy the new images."
