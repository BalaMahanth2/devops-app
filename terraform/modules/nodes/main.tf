terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0"
    }
  }
}

# Who may use the role: EC2 machines.
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# An instance profile is how an EC2 machine carries an IAM role.
resource "aws_iam_instance_profile" "this" {
  name = var.role_name
  role = aws_iam_role.this.name
}

# Tells the cluster to accept machines that carry the node role.
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.this.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
    ])
  }
}

# The newest EKS machine image for this Kubernetes version, published by AWS.
data "aws_ami" "this" {
  most_recent = true
  owners      = ["602401143452"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-standard-${var.kubernetes_version}-v*"]
  }
}

locals {
  # Read by "nodeadm" on first boot: it tells the machine which cluster to join.
  user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${var.cluster_name}
        apiServerEndpoint: ${var.cluster_endpoint}
        certificateAuthority: ${var.cluster_certificate_authority}
        cidr: ${var.cluster_service_cidr}

    --BOUNDARY--
  EOT
}

resource "aws_instance" "this" {
  count = var.node_count

  ami                    = data.aws_ami.this.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.cluster_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.this.name
  user_data              = local.user_data

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name                                        = "${var.cluster_name}-node-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  # A machine can only join once its role has its policies
  # and the cluster accepts that role.
  depends_on = [
    aws_iam_role_policy_attachment.this,
    kubernetes_config_map_v1.aws_auth,
  ]
}

# Opens the app's port on the nodes, only for the allowed addresses.
resource "aws_vpc_security_group_ingress_rule" "node_port" {
  security_group_id = var.cluster_security_group_id
  description       = "App NodePort"
  cidr_ipv4         = var.allow_cidr
  ip_protocol       = "tcp"
  from_port         = var.node_port
  to_port           = var.node_port
}
