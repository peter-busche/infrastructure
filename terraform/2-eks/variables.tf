variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "project1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "admin_user_arn" {
  description = "ARN of the IAM user to grant cluster admin access"
  type        = string
  sensitive   = true
}
