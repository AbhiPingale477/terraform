```hcl
provider "aws" {
  region = "ap-south-1"
}

# Get Ubuntu 24.04 EKS AMI
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/eks/24.04/1.35/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster2" {
  name = "eks-cluster-example987"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster2.name
}

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Get Subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = ["ap-south-1a", "ap-south-1b"]
  }
}

# Create EKS Cluster
resource "aws_eks_cluster" "cluster2" {
  name     = "cluster2"
  role_arn = aws_iam_role.cluster2.arn
  version  = "1.35"

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# Worker Node IAM Role
resource "aws_iam_role" "node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Worker Node Policies
resource "aws_iam_role_policy_attachment" "worker_node" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Ubuntu Launch Template
resource "aws_launch_template" "ubuntu" {
  name          = "eks-ubuntu-template"
  image_id      = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = "t3.medium"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    /etc/eks/bootstrap.sh cluster2
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ubuntu-eks-worker"
    }
  }
}

# Ubuntu EKS Node Group
resource "aws_eks_node_group" "ubuntu_nodes" {
  cluster_name    = aws_eks_cluster.cluster2.name
  node_group_name = "ubuntu-node-group"
  node_role_arn   = aws_iam_role.node_role.arn

  subnet_ids = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.ubuntu.id
    version = tostring(aws_launch_template.ubuntu.latest_version)
  }

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_node,
    aws_iam_role_policy_attachment.cni,
    aws_iam_role_policy_attachment.ecr
  ]
}
```
