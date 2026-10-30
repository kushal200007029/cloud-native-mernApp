
# ==================================================
# PATHNEX - ANSIBLE EC2 AUTOMATION
# Region: ap-south-1
# OS: Ubuntu 24.04 LTS
# ==================================================


# --------------------------------------------------
# 1. Ubuntu 24.04 AMI
# --------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# --------------------------------------------------
# 2. IAM Role for Ansible EC2
# --------------------------------------------------

resource "aws_iam_role" "ansible" {
  name = "pathnex-ansible-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# SSM permissions
resource "aws_iam_role_policy_attachment" "ansible_ssm" {
  role       = aws_iam_role.ansible.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EKS DescribeCluster permission
resource "aws_iam_role_policy" "ansible_eks" {
  name = "pathnex-ansible-eks-access"
  role = aws_iam_role.ansible.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster"
      ]
      Resource = module.eks.cluster_arn
    }]
  })
}

# EC2 instance profile
resource "aws_iam_instance_profile" "ansible" {
  name = "pathnex-ansible-instance-profile"
  role = aws_iam_role.ansible.name
}


# --------------------------------------------------
# 3. EKS Access Entry
# --------------------------------------------------

resource "aws_eks_access_entry" "ansible" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.ansible.arn
  type          = "STANDARD"
}

# Cluster administrator access
resource "aws_eks_access_policy_association" "ansible" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.ansible.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.ansible
  ]
}


# --------------------------------------------------
# 4. Ansible EC2 Security Group
# --------------------------------------------------

resource "aws_security_group" "ansible" {
  name        = "pathnex-ansible-sg"
  description = "Ansible EC2 security group"
  vpc_id      = var.vpc_id

  # No inbound SSH.
  # Outbound internet and AWS service access.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pathnex-ansible-sg"
  }
}


# --------------------------------------------------
# 5. Allow Ansible EC2 to access EKS API
# --------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "eks_from_ansible" {
  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = aws_security_group.ansible.id

  description = "Allow Ansible EC2 to access EKS Kubernetes API"

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}


# --------------------------------------------------
# 6. Ansible EC2 Instance
# --------------------------------------------------

resource "aws_instance" "ansible" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_ids[0]
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ansible.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ansible.name

  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }


  # ==================================================
  # 7. AUTOMATED SERVER BOOTSTRAP
  # ==================================================

  user_data = <<-BOOTSTRAP
    #!/bin/bash

    set -euxo pipefail

    exec > >(tee -a /var/log/pathnex-bootstrap.log) 2>&1

    echo "Starting Pathnex Ansible server bootstrap"

    # ------------------------------------------------
    # Create SSM user if not already present
    # ------------------------------------------------

    if ! id ssm-user >/dev/null 2>&1; then
      useradd --create-home --shell /bin/bash ssm-user
    fi

    # ------------------------------------------------
    # Configure passwordless sudo for SSM user
    # ------------------------------------------------

    echo "ssm-user ALL=(ALL) NOPASSWD:ALL" \
      > /etc/sudoers.d/ssm-user

    chmod 0440 /etc/sudoers.d/ssm-user

    # Validate sudo configuration before continuing
    visudo -cf /etc/sudoers.d/ssm-user

    mkdir -p /home/ssm-user

    # ------------------------------------------------
    # Install system dependencies and Ansible
    # ------------------------------------------------

    apt-get update

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ansible \
      python3 \
      python3-pip \
      python3-venv \
      curl \
      unzip \
      ca-certificates \
      git \
      jq

    # ------------------------------------------------
    # Install AWS CLI v2
    # ------------------------------------------------

    cd /tmp

    curl -fsSL \
      "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o awscliv2.zip

    unzip -q awscliv2.zip

    ./aws/install --update

    # ------------------------------------------------
    # Install kubectl v1.36
    # ------------------------------------------------

    curl -fsSLo kubectl \
      "https://dl.k8s.io/release/v1.36.0/bin/linux/amd64/kubectl"

    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # ------------------------------------------------
    # Install Helm 3
    # ------------------------------------------------

    curl -fsSL \
      https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      -o get_helm.sh

    chmod 700 get_helm.sh

    ./get_helm.sh

    # ------------------------------------------------
    # Configure SSM
    # ------------------------------------------------

    systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service || true
    systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service || true


    # ==================================================
    # 8. CREATE ANSIBLE PROJECT STRUCTURE
    # ==================================================

    PROJECT_DIR="/opt/pathnex-ansible"

    mkdir -p "$PROJECT_DIR"

    mkdir -p "$PROJECT_DIR/inventory"
    mkdir -p "$PROJECT_DIR/playbooks"
    mkdir -p "$PROJECT_DIR/roles"
    mkdir -p "$PROJECT_DIR/roles/common/tasks"
    mkdir -p "$PROJECT_DIR/roles/common/handlers"
    mkdir -p "$PROJECT_DIR/roles/common/defaults"
    mkdir -p "$PROJECT_DIR/roles/common/vars"
    mkdir -p "$PROJECT_DIR/roles/common/templates"
    mkdir -p "$PROJECT_DIR/roles/common/files"
    mkdir -p "$PROJECT_DIR/roles/common/meta"
    mkdir -p "$PROJECT_DIR/group_vars"
    mkdir -p "$PROJECT_DIR/files"
    mkdir -p "$PROJECT_DIR/templates"


    # ------------------------------------------------
    # 9. Generate ansible.cfg
    # ------------------------------------------------

    cat > "$PROJECT_DIR/ansible.cfg" <<'ANSIBLECFG'
    [defaults]
    inventory = ./inventory/hosts
    host_key_checking = False
    retry_files_enabled = False
    roles_path = ./roles
    interpreter_python = auto_silent
    deprecation_warnings = False

    [privilege_escalation]
    become = False
    ANSIBLECFG


    # ------------------------------------------------
    # 10. Generate inventory
    # ------------------------------------------------

    cat > "$PROJECT_DIR/inventory/hosts" <<'INVENTORY'
    [local]
    localhost ansible_connection=local
    INVENTORY


    # ------------------------------------------------
    # 11. Generate group variables
    # ------------------------------------------------

    cat > "$PROJECT_DIR/group_vars/all.yml" <<'GROUPVARS'
    ---
    aws_region: ap-south-1
    eks_cluster_name: pathnex-eks
    ansible_project_dir: /opt/pathnex-ansible
    GROUPVARS


    # ------------------------------------------------
    # 12. Generate environment verification playbook
    # ------------------------------------------------

    cat > "$PROJECT_DIR/playbooks/verify-environment.yml" <<'PLAYBOOK'
    ---
    - name: Verify Pathnex Ansible server
      hosts: local
      connection: local
      gather_facts: false

      tasks:
        - name: Verify Python
          command: python3 --version
          changed_when: false

        - name: Verify Ansible
          command: ansible --version
          changed_when: false

        - name: Verify AWS CLI
          command: aws --version
          changed_when: false

        - name: Verify kubectl
          command: kubectl version --client
          changed_when: false

        - name: Verify Helm
          command: helm version
          changed_when: false

        - name: Verify AWS identity
          command: aws sts get-caller-identity
          changed_when: false
    PLAYBOOK


    # ------------------------------------------------
    # 13. Configure AWS CLI default region
    # ------------------------------------------------

    mkdir -p /home/ssm-user/.aws

    cat > /home/ssm-user/.aws/config <<'AWSCONFIG'
    [default]
    region = ap-south-1
    output = json
    AWSCONFIG


    # ------------------------------------------------
    # 14. Configure EKS kubeconfig
    # ------------------------------------------------

    mkdir -p /home/ssm-user/.kube

    chown -R ssm-user:ssm-user /home/ssm-user/.aws
    chown -R ssm-user:ssm-user /home/ssm-user/.kube

    KUBECTL_READY=false

    for attempt in $(seq 1 30); do

      echo "Attempt $attempt: Configuring EKS access"

      if runuser -u ssm-user -- env HOME=/home/ssm-user \
        aws eks update-kubeconfig \
        --region ap-south-1 \
        --name pathnex-eks \
        --kubeconfig /home/ssm-user/.kube/config; then

        if runuser -u ssm-user -- env HOME=/home/ssm-user \
          kubectl get nodes; then

          KUBECTL_READY=true
          break

        fi
      fi

      sleep 10

    done

    if [ "$KUBECTL_READY" != "true" ]; then
      echo "WARNING: EKS connectivity not ready during bootstrap."
      echo "Kubeconfig was attempted. Check bootstrap logs."
    fi


    # ------------------------------------------------
    # 15. Set project permissions
    # ------------------------------------------------

    chown -R ssm-user:ssm-user "$PROJECT_DIR"

    chmod -R 755 "$PROJECT_DIR"

    # ------------------------------------------------
    # 16. Run initial Ansible verification
    # ------------------------------------------------

    runuser -u ssm-user -- env HOME=/home/ssm-user \
      bash -c "cd $PROJECT_DIR && ansible-playbook playbooks/verify-environment.yml"

    echo "Pathnex Ansible bootstrap completed"

  BOOTSTRAP


  # ------------------------------------------------
  # 17. Terraform dependency ordering
  # ------------------------------------------------

  depends_on = [
    aws_iam_role_policy_attachment.ansible_ssm,
    aws_iam_role_policy.ansible_eks,
    aws_eks_access_policy_association.ansible,
    aws_vpc_security_group_ingress_rule.eks_from_ansible
  ]

  tags = {
    Name = "pathnex-ansible-server"
  }
}


# --------------------------------------------------
# 18. Terraform Outputs
# --------------------------------------------------

output "ansible_instance_id" {
  description = "Ansible EC2 instance ID"
  value       = aws_instance.ansible.id
}

output "ansible_public_ip" {
  description = "Ansible EC2 public IP"
  value       = aws_instance.ansible.public_ip
}

output "ansible_iam_role_arn" {
  description = "Ansible EC2 IAM role ARN"
  value       = aws_iam_role.ansible.arn
}
