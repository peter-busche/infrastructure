#!/usr/bin/env bash
set -euo pipefail

# Use root AWS profile to create infrastructure
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

# Extract username from ARN (e.g., arn:aws:iam::123456789:user/peter-cli -> peter-cli)
export ADMIN_USERNAME="${ADMIN_USER_ARN##*/}"

echo "=== Starting Project1 Infrastructure ==="

echo ""
echo "[1/6] Initializing VPC..."
terraform -chdir="$REPO_ROOT/terraform/1-vpc" init

echo ""
echo "[2/6] Applying VPC..."
terraform -chdir="$REPO_ROOT/terraform/1-vpc" apply -auto-approve

echo ""
echo "[3/6] Initializing EKS..."
terraform -chdir="$REPO_ROOT/terraform/2-eks" init

echo ""
echo "[4/6] Applying EKS cluster (creates cluster and IAM access entries)..."
terraform -chdir="$REPO_ROOT/terraform/2-eks" apply -auto-approve \
  -var="admin_user_arn=$ADMIN_USER_ARN"

echo ""
echo "[5/7] Creating rag-api ECR repository..."
aws ecr create-repository \
  --repository-name rag-api \
  --region us-west-2 \
  --image-tag-mutability MUTABLE 2>/dev/null || \
  echo "ECR repository 'rag-api' already exists, skipping."

echo ""
echo "[6/7] Configuring kubectl..."
aws eks update-kubeconfig --name project1-dev --region us-west-2

echo ""
echo "[7/7] Deploying cluster manifests (namespaces, storage, metrics)..."
# Wait for cluster API to be available
echo "Waiting for cluster to be fully ready..."
for i in {1..30}; do
  if kubectl cluster-info &>/dev/null; then
    echo "Cluster is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for cluster API..."
  sleep 10
done

# Apply cluster manifests
kubectl apply -k "$REPO_ROOT/eks-manifests/namespaces/"
kubectl apply -k "$REPO_ROOT/eks-manifests/kube-system/"

echo ""
echo "=== Infrastructure is up ==="
echo "Run 'kubectl get nodes' to verify cluster connectivity."
