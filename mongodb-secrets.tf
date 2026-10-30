
# ==================================================
# PATHNEX - MONGODB CREDENTIALS
# ==================================================

resource "random_password" "mongodb" {
  length  = 40
  special = false
}

# --------------------------------------------------
# AWS SECRETS MANAGER
# --------------------------------------------------

resource "aws_secretsmanager_secret" "mongodb" {
  name                    = "pathnex/mongodb"
  description             = "Pathnex MongoDB credentials"
  recovery_window_in_days = 7

  tags = {
    Project   = "Pathnex"
    Component = "MongoDB"
    ManagedBy = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "mongodb" {
  secret_id = aws_secretsmanager_secret.mongodb.id

  secret_string = jsonencode({
    username = "pathnexadmin"
    password = random_password.mongodb.result
  })
}

# --------------------------------------------------
# IAM ROLE FOR EXTERNAL SECRETS OPERATOR
# --------------------------------------------------

resource "aws_iam_role" "external_secrets" {
  name = "pathnex-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "pods.eks.amazonaws.com"
      }

      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = {
    Project   = "Pathnex"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "pathnex-read-mongodb-secret"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ]

      Resource = aws_secretsmanager_secret.mongodb.arn
    }]
  })
}

# --------------------------------------------------
# EKS POD IDENTITY ASSOCIATION
# --------------------------------------------------

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [
    aws_iam_role_policy.external_secrets
  ]
}

# --------------------------------------------------
# EXTERNAL SECRETS OPERATOR
# --------------------------------------------------

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.11.0"

  namespace        = "external-secrets"
  create_namespace = true

  wait    = true
  atomic  = true
  timeout = 600

  depends_on = [
    aws_eks_pod_identity_association.external_secrets
  ]
}

# --------------------------------------------------
# OUTPUTS
# --------------------------------------------------

output "mongodb_secret_arn" {
  description = "AWS Secrets Manager ARN for MongoDB credentials"
  value       = aws_secretsmanager_secret.mongodb.arn
}

output "external_secrets_role_arn" {
  description = "IAM role used by External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}
