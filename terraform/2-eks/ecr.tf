# -----------------------------------------------------------------------------
# ECR Repository for Mirrored Container Images
# -----------------------------------------------------------------------------
# A single "mirror" repo holds all mirrored third-party images, differentiated
# by tag (e.g., argocd-v3-0-6, redis-7-2-7-alpine). This matches the pattern
# used in the company infrastructure repo.
#
# To push an image:
#   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <ecr_url>
#   docker tag <source_image> <ecr_url>/mirror:<tag>
#   docker push <ecr_url>/mirror:<tag>

resource "aws_ecr_repository" "mirror" {
  name                 = "mirror"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
