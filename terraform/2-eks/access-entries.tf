resource "aws_eks_access_entry" "root" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  type              = "STANDARD"

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "root_admin" {
  cluster_name       = module.eks.cluster_name
  principal_arn      = aws_eks_access_entry.root.principal_arn
  policy_arn         = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}


resource "aws_eks_access_entry" "admin_user" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = var.admin_user_arn
  type              = "STANDARD"

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "admin_user_policy" {
  cluster_name       = module.eks.cluster_name
  principal_arn      = aws_eks_access_entry.admin_user.principal_arn
  policy_arn         = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

data "aws_caller_identity" "current" {}
