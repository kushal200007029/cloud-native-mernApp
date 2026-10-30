
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = ["106.210.235.81/32"]

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }

    aws-ebs-csi-driver = {
      pod_identity_association = [
        {
          role_arn        = module.ebs_csi_pod_identity.iam_role_arn
          service_account = "ebs-csi-controller-sa"
        }
      ]
    }
  }


  eks_managed_node_groups = {
    general = {
      name           = "pathnex-general"
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 3
      desired_size = 2

      disk_size = 30

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.9.0"

  name = "${var.cluster_name}-ebs-csi"

  attach_aws_ebs_csi_policy = true
}


# Identify subnets belonging to the Pathnex EKS cluster
resource "aws_ec2_tag" "eks_cluster" {
  for_each = toset(var.subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

# Identify public subnets for internet-facing load balancers
resource "aws_ec2_tag" "public_elb" {
  for_each = toset(var.subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
