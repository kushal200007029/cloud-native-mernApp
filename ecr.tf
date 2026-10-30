
# ==================================================
# PATHNEX - AMAZON ECR CONFIGURATION
# Region: ap-south-1
# ==================================================

# --------------------------------------------------
# 1. Create ECR repositories
# --------------------------------------------------

resource "aws_ecr_repository" "pathnex" {
  for_each = toset([
    "frontend",
    "backend"
  ])

  name                 = "pathnex-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Project     = "Pathnex"
    Environment = "Production"
    Component   = each.key
    ManagedBy   = "Terraform"
  }
}

# --------------------------------------------------
# 2. ECR Lifecycle Policies
# --------------------------------------------------

resource "aws_ecr_lifecycle_policy" "pathnex" {
  for_each = aws_ecr_repository.pathnex

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the latest 20 tagged images"

        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 20
        }

        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 7 days"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --------------------------------------------------
# 3. ECR Outputs
# --------------------------------------------------

output "ecr_repository_urls" {
  description = "Pathnex ECR repository URLs"

  value = {
    for name, repository in aws_ecr_repository.pathnex :
    name => repository.repository_url
  }
}

output "ecr_registry_id" {
  description = "AWS account registry ID"

  value = aws_ecr_repository.pathnex["frontend"].registry_id
}
