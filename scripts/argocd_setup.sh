#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load environment variables from .env file if it exists
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

# Check that required environment variables are set
if [ -z "${GITHUB_USERNAME:-}" ]; then
  echo "Error: GITHUB_USERNAME environment variable not set. Please add it to your .env file."
  exit 1
fi

if [ -z "${GITHUB_PAT:-}" ]; then
  echo "Error: GITHUB_PAT environment variable not set. Please add it to your .env file."
  echo ""
  echo "To create a GitHub PAT:"
  echo "  1. Go to https://github.com/settings/tokens"
  echo "  2. Click 'Generate new token (classic)'"
  echo "  3. Name it (e.g., 'argocd-project1')"
  echo "  4. Select scope: 'repo'"
  echo "  5. Copy the token and add to .env as GITHUB_PAT"
  exit 1
fi

echo "=== Setting up ArgoCD ==="
echo ""
echo "[1/6] Checking prerequisites..."

# Check docker
if ! command -v docker &> /dev/null; then
  echo "Error: docker is not installed or not in PATH"
  exit 1
fi
echo "✓ docker is available"

# Check aws
if ! command -v aws &> /dev/null; then
  echo "Error: aws CLI is not installed or not in PATH"
  exit 1
fi
echo "✓ aws CLI is available"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo "Error: kubectl is not installed or not in PATH"
  exit 1
fi
echo "✓ kubectl is available"

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
  echo "Error: Cannot connect to Kubernetes cluster. Make sure your kubeconfig is set up."
  exit 1
fi
echo "✓ Kubernetes cluster is reachable"

echo ""
echo "[2/6] Mirroring images to ECR..."

# Get ECR repository URL from Terraform output
echo "Fetching ECR repository URL from Terraform..."
ECR_URL=$(terraform -chdir="$REPO_ROOT/terraform/2-eks" output -raw ecr_repository_url 2>/dev/null)
if [ -z "$ECR_URL" ]; then
  echo "Error: Could not get ECR repository URL from Terraform. Make sure 2-eks was applied."
  exit 1
fi
echo "ECR URL: $ECR_URL"

# Pull images from upstream registries (ARM64 for EKS t4g.small Graviton nodes)
echo "Pulling ArgoCD image..."
docker pull --platform linux/arm64 quay.io/argoproj/argocd:v3.0.6
echo "✓ ArgoCD image pulled"

echo "Pulling Redis image..."
docker pull --platform linux/arm64 redis:7.2.7-alpine
echo "✓ Redis image pulled"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin "$ECR_URL" &>/dev/null
echo "✓ Logged in to ECR"

# Tag and push images
echo "Tagging and pushing ArgoCD image..."
docker tag quay.io/argoproj/argocd:v3.0.6 "$ECR_URL:argocd-v3-0-6"
docker push "$ECR_URL:argocd-v3-0-6"
echo "✓ ArgoCD image pushed"

echo "Tagging and pushing Redis image..."
docker tag redis:7.2.7-alpine "$ECR_URL:redis-7-2-7-alpine"
docker push "$ECR_URL:redis-7-2-7-alpine"
echo "✓ Redis image pushed"

echo ""
echo "[3/6] Installing ArgoCD..."

# Wait for any pre-existing terminating argocd namespace to clear
if kubectl get namespace argocd &>/dev/null; then
  PHASE=$(kubectl get namespace argocd -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$PHASE" = "Terminating" ]; then
    echo "  argocd namespace is Terminating — waiting up to 120s for it to be deleted..."
    if ! kubectl wait --for=delete namespace/argocd --timeout=120s 2>/dev/null; then
      echo "  Timeout reached; force-clearing finalizers on argocd namespace..."
      kubectl patch namespace argocd \
        -p '{"metadata":{"finalizers":[]}}' --type=merge
      kubectl wait --for=delete namespace/argocd --timeout=30s
    fi
    echo "✓ argocd namespace fully removed"
  fi
fi

envsubst < <(kubectl kustomize "$REPO_ROOT/eks-manifests/argocd/") | kubectl apply -f -
echo "✓ ArgoCD manifests applied"

echo ""
echo "[4/6] Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
echo "✓ ArgoCD server is ready"

echo ""
echo "[5/6] Applying repository secrets..."

# Create repo secret for project1_infrastructure
echo "Applying secret for project1_infrastructure repo..."
envsubst < "$REPO_ROOT/eks-manifests/argocd/repos/repo-secret.yaml.example" | kubectl apply -f -
echo "✓ project1_infrastructure repo secret applied"

echo ""
echo "[6/6] Applying ArgoCD Applications..."

# Apply namespaces app
echo "Applying namespaces Application..."
envsubst < "$REPO_ROOT/eks-manifests/argocd/argo-apps/namespaces.yaml" | kubectl apply -f -
echo "✓ namespaces Application applied"

# Apply kube-system app
echo "Applying kube-system Application..."
envsubst < "$REPO_ROOT/eks-manifests/argocd/argo-apps/kube-system.yaml" | kubectl apply -f -
echo "✓ kube-system Application applied"

# Apply rag-api app
echo "Applying rag-api Application..."
envsubst < "$REPO_ROOT/eks-manifests/argocd/argo-apps/rag-api.yaml" | kubectl apply -f -
echo "✓ rag-api Application applied"

echo ""
echo "=== ArgoCD Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Wait for ArgoCD Applications to sync:"
echo "   kubectl get applications -n argocd"
echo ""
echo "2. Access the ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Open: https://localhost:8080"
echo ""
echo "3. Get the admin password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo "4. After syncing rag_api repo, make sure it has Kubernetes manifests in the 'k8s/' directory"
echo "   (Update the rag-api.yaml if you use a different directory name)"
echo ""
