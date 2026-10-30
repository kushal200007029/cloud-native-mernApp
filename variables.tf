
variable "aws_region" {
  description = "AWS region for Pathnex infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_id" {
  description = "Existing default VPC ID"
  type        = string
  default     = "vpc-05d888adf774aad42"
}

variable "subnet_ids" {
  description = "Existing default VPC subnet IDs across three Availability Zones"
  type        = list(string)
  default = [
    "subnet-082aa2ba6f90d821c",
    "subnet-01d3bca10654e359e",
    "subnet-01346ddd330508f87"
  ]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "pathnex-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.36"
}
