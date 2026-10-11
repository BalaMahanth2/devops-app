module "registry" {
  source = "../../modules/registry"

  name = var.name
  # The account is thrown away after the session, so the images can go with it.
  force_delete = true
}

# ---------- Network: reuse the account's default network ----------

data "aws_vpc" "default" {
  default = true
}

# EKS cannot place its control plane in zone use1-az3.
data "aws_availability_zones" "usable" {
  state            = "available"
  exclude_zone_ids = ["use1-az3"]
}

data "aws_subnets" "usable" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.usable.names
  }
}

# The public address of this laptop's network, used when allow_cidr is empty.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  subnet_ids = slice(sort(data.aws_subnets.usable.ids), 0, 3)
  allow_cidr = coalesce(var.allow_cidr, "${chomp(data.http.my_ip.response_body)}/32")
}

# ---------- Cluster and nodes ----------

module "cluster" {
  source = "../../modules/cluster"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = local.subnet_ids
  # The sandbox only lets EKS use a role with exactly this name.
  role_name = "eksClusterRole"
}

module "nodes" {
  source = "../../modules/nodes"

  cluster_name                  = module.cluster.name
  cluster_endpoint              = module.cluster.endpoint
  cluster_certificate_authority = module.cluster.certificate_authority
  cluster_service_cidr          = module.cluster.service_cidr
  cluster_security_group_id     = module.cluster.security_group_id
  kubernetes_version            = var.kubernetes_version
  role_name                     = "AmazonEKSNodeRole"
  subnet_ids                    = local.subnet_ids
  node_count                    = var.node_count
  node_port                     = var.node_port
  allow_cidr                    = local.allow_cidr
}
