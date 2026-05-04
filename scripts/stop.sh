#!/usr/bin/env bash
set -euo pipefail

# Use root AWS profile to destroy infrastructure
export AWS_PROFILE=root

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load environment variables from .env file if it exists
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

# Check that required environment variables are set
if [ -z "${ADMIN_USER_ARN:-}" ]; then
  echo "Error: ADMIN_USER_ARN environment variable not set. Please add it to your .env file."
  exit 1
fi

echo "=== Tearing down Project1 Infrastructure ==="

echo ""
echo "[1/7] Removing ArgoCD and applications..."
# Remove ArgoCD manifests first (before cluster is destroyed)
kubectl delete -k "$REPO_ROOT/eks-manifests/argocd/" --ignore-not-found=true || true

echo ""
echo "[2/7] Removing cluster manifests (namespaces, storage, metrics)..."
# Remove manifests before destroying the cluster
kubectl delete -k "$REPO_ROOT/eks-manifests/kube-system/" --ignore-not-found=true || true
kubectl delete -k "$REPO_ROOT/eks-manifests/namespaces/" --ignore-not-found=true || true

echo ""
echo "[3/7] Initializing EKS..."
terraform -chdir="$REPO_ROOT/terraform/2-eks" init

echo ""
echo "[4/7] Destroying EKS..."
terraform -chdir="$REPO_ROOT/terraform/2-eks" destroy -auto-approve \
  -var="admin_user_arn=$ADMIN_USER_ARN"

echo ""
echo "[5/7] Initializing VPC..."
terraform -chdir="$REPO_ROOT/terraform/1-vpc" init

echo ""
echo "[6/7] Destroying VPC..."
terraform -chdir="$REPO_ROOT/terraform/1-vpc" destroy -auto-approve

echo ""
echo "[7/7] Cleaning up ECR..."
# Delete rag-api repo entirely (recreated by start.sh each morning)
aws ecr delete-repository \
  --repository-name rag-api \
  --region us-west-2 \
  --force 2>/dev/null || true

# Delete all images in the mirror repo (repo itself is managed by Terraform in 2-eks)
aws ecr describe-images \
  --repository-name mirror \
  --region us-west-2 \
  --query 'imageDetails[].{imageTag:imageTags[0],imageDigest:imageDigest}' \
  --output json | jq -r '.[] | select(.imageTag != null) | "imageDigest=\(.imageDigest)"' | \
  xargs -I {} aws ecr batch-delete-image \
    --repository-name mirror \
    --region us-west-2 \
    --image-ids {} 2>/dev/null || true

echo "✓ ECR cleanup complete"

echo ""
echo "=== Infrastructure is down ==="
