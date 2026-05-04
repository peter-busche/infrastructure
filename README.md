# Project1 Infrastructure

A sandbox for exploring Kubernetes and ArgoCD using ephemeral AWS infrastructure.

This repo automates the daily creation and destruction of an EKS cluster in AWS, allowing for cost-effective experimentation with container orchestration and GitOps workflows.

## Tech Stack

- **Terraform** — Infrastructure as code for AWS
- **EKS** — Managed Kubernetes cluster (us-west-2)
- **ArgoCD** — GitOps continuous deployment
- **S3 + DynamoDB** — Terraform remote state backend

## Quick Start

```bash
# Spin up EKS cluster + configure ArgoCD
./scripts/start.sh
./scripts/argocd_setup.sh

# Tear down all daily resources
./scripts/stop.sh
```

## Project Structure

- `terraform/` — Terraform modules for VPC, EKS, and bootstrap infrastructure
- `eks-manifests/` — Kubernetes manifests deployed to the cluster
- `gitops/` — ArgoCD configuration and application definitions
- `scripts/` — Automation for infrastructure lifecycle management
- `docs/` — Architecture documentation (C4 diagrams)

## How It Works

1. **start.sh** — Applies Terraform modules (VPC → EKS) and configures kubectl access
2. **argocd_setup.sh** — Installs and configures ArgoCD on the cluster
3. **stop.sh** — Destroys daily resources (EKS → VPC), preserving the bootstrap layer

The bootstrap layer (S3 state bucket + DynamoDB lock table) is persistent and only created once.

