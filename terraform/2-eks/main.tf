# Local values computed from variables and remote state
# These pull VPC configuration created by the 1-vpc module
locals {
  cluster_name    = "${var.project_name}-${var.environment}" # e.g., "project1-dev"
  vpc_id          = data.terraform_remote_state.vpc.outputs.vpc_id # VPC ID from 1-vpc module
  private_subnets = data.terraform_remote_state.vpc.outputs.private_subnet_ids # Private subnet IDs from 1-vpc module (where EKS nodes will run)
}

# -----------------------------------------------------------------------------
# EKS Cluster using the official AWS Terraform module
# This creates the Kubernetes control plane (API server, etcd, scheduler, etc.)
# The module handles all the complexity of setting up IAM roles, security groups, etc.
# -----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name # Cluster name: "project1-dev"
  cluster_version = var.cluster_version # Kubernetes version (from variables)

  # Network configuration: place cluster in the VPC and private subnets created by 1-vpc module
  vpc_id     = local.vpc_id # VPC ID where the cluster will operate
  subnet_ids = local.private_subnets # Private subnets where worker nodes will be placed

  # API endpoint access control
  # Public endpoint allows kubectl access from your machine (developer workflows)
  # Private endpoint allows pod-to-API communication within the cluster
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # Enable IAM Roles for Service Accounts (IRSA)
  # This creates an OIDC provider so Kubernetes service accounts can assume IAM roles
  # Required for EBS CSI driver and other AWS integrations
  enable_irsa = true

  # EKS Managed Addons
  # These are Kubernetes add-ons provided and maintained by AWS
  cluster_addons = {
    vpc-cni = {
      # AWS VPC CNI plugin: handles pod networking (IP assignment, security groups)
      most_recent = true
    }
    coredns = {
      # DNS service for the cluster: resolves service names to IPs
      most_recent = true
    }
    kube-proxy = {
      # Network proxy: manages iptables rules for pod-to-pod communication
      most_recent = true
    }
    aws-ebs-csi-driver = {
      # EBS CSI driver: allows pods to request and use AWS EBS volumes
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn # IAM role for the EBS CSI controller
    }
  }

  # Managed Node Group
  # AWS manages the EC2 instances and auto-scaling group; you only define the configuration
  eks_managed_node_groups = {
    default = {
      name           = "${local.cluster_name}-nodes" # Name: "project1-dev-nodes"
      instance_types = ["t4g.small"] # Compute instance type (ARM64 Graviton2, burstable, suitable for dev)
      capacity_type  = "ON_DEMAND" # Pay per second (not spot, to avoid interruptions)
      ami_type       = "AL2023_ARM_64_STANDARD" # Amazon Linux 2023 ARM64 with EKS optimizations

      # Node count is fixed at 2 (min = max = desired = 2)
      min_size     = 2 # Minimum number of nodes
      max_size     = 2 # Maximum number of nodes
      desired_size = 2 # Target number of nodes to maintain

      # EBS root volume configuration for each node
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda" # Root device
          ebs = {
            volume_size = 20 # 20 GB root volume
            volume_type = "gp3" # General purpose SSD
            encrypted   = true # Encrypt the volume at rest
          }
        }
      }

      # Metadata service security settings
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # IMDSv2 enforced (more secure than IMDSv1)
        http_put_response_hop_limit = 1 # Pods cannot reach the metadata service (only host can)
      }
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IRSA (IAM Roles for Service Accounts) Role for EBS CSI Driver
# This creates an IAM role that the EBS CSI controller pod can assume
# The pod uses this role to call AWS EBS APIs (create, attach, mount volumes)
# This is more secure than embedding AWS credentials in the pod
# Connection: EKS OIDC provider (created above) allows Kubernetes service accounts to assume AWS IAM roles
# -----------------------------------------------------------------------------
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi" # Role name: "project1-dev-ebs-csi"
  attach_ebs_csi_policy = true # Attach AWS managed policy for EBS CSI driver permissions

  # Connect this IAM role to the EBS CSI controller service account in the cluster
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn # OIDC provider from the EKS cluster
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"] # The service account that will use this role
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
