# Credentials come from the shell: export AWS_PROFILE=kk
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "devops-app"
      ManagedBy = "terraform"
    }
  }
}

# Talks to the cluster that this same configuration creates.
# The AWS CLI fetches a fresh token each time one is needed.
provider "kubernetes" {
  host                   = module.cluster.endpoint
  cluster_ca_certificate = base64decode(module.cluster.certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.name, "--region", var.region]
  }
}
