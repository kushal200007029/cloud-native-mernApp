
# ==================================================
# PATHNEX - GITHUB ACTIONS OIDC
# ==================================================

# --------------------------------------------------
# 1. GitHub OIDC Provider
# --------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Project   = "Pathnex"
    ManagedBy = "Terraform"
  }
}

# --------------------------------------------------
# 2. IAM Role for GitHub Actions
# --------------------------------------------------

resource "aws_iam_role" "github_actions" {
  name = "pathnex-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }

      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:kushal200007029/cloud-native-mernApp:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Project   = "Pathnex"
    ManagedBy = "Terraform"
  }
}

# --------------------------------------------------
# 3. ECR Permissions
# --------------------------------------------------

resource "aws_iam_role_policy" "github_ecr" {
  name = "pathnex-github-ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage"
        ]

        Resource = [
          aws_ecr_repository.pathnex["frontend"].arn,
          aws_ecr_repository.pathnex["backend"].arn
        ]
      }
    ]
  })
}

# --------------------------------------------------
# 4. GitHub Actions Role Output
# --------------------------------------------------

output "github_actions_role_arn" {
  description = "IAM role assumed by GitHub Actions using OIDC"

  value = aws_iam_role.github_actions.arn
}
