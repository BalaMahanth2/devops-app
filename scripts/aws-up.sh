#!/usr/bin/env bash
# Starts the whole app on AWS in a short-lived sandbox account:
# registry (ECR) and image, EKS cluster, two self-managed nodes, Helm release.
#
# Usage:  export AWS_PROFILE=kk
#         scripts/aws-up.sh [image-tag]
#
# Safe to run again: every step first checks whether its work is already done.
set -euo pipefail

# Git Bash rewrites arguments that look like Unix paths. Switch that off.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" AWS_PAGER=""
export AWS_REGION="${AWS_REGION:-us-east-1}"
: "${AWS_PROFILE:?Set AWS_PROFILE first, for example: export AWS_PROFILE=kk}"

CLUSTER="devops-app"
K8S_VERSION="1.35"
NODE_COUNT=2
NODE_TYPE="t3.medium"
NODE_PORT=30080
NAMESPACE="devops-app"
CONTEXT="eks-devops-app"
CHART="kubernetes/helm/devops-app"
# Who may open the app. Default: only the network this laptop is on.
# For any machine on the internet:  ALLOW_CIDR=0.0.0.0/0 scripts/aws-up.sh
ALLOW_CIDR="${ALLOW_CIDR:-}"

cd "$(dirname "$0")/.."
# Windows programs need relative paths here, so temporary files live in the repo.
WORK=".aws-work"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

step() { echo; echo "==> $*"; }
k() { kubectl --context "$CONTEXT" "$@"; }

step "1/8 Who am I, and which image?"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
git fetch --quiet origin develop
TAG="${1:-sha-$(git rev-parse --short origin/develop)}"
echo "account $ACCOUNT_ID, region $AWS_REGION, image tag $TAG"

step "2/8 Registry and image"
if ! aws ecr describe-repositories --repository-names devops-app >/dev/null 2>&1; then
  aws ecr create-repository --repository-name devops-app --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true --query repository.repositoryUri --output text
fi
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR" >/dev/null
if aws ecr describe-images --repository-name devops-app --image-ids "imageTag=$TAG" >/dev/null 2>&1; then
  echo "image $TAG is already in ECR"
else
  # Copy, never rebuild: the digest in ECR is the one CI scanned and signed.
  docker buildx imagetools create --tag "$ECR/devops-app:$TAG" "ghcr.io/balamahanth2/devops-app:$TAG"
fi

step "3/8 IAM roles"
NEW_IAM=0
ensure_role() {
  local name="$1" service="$2" policy
  shift 2
  if aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    echo "role $name exists"
    return
  fi
  printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"%s"},"Action":"sts:AssumeRole"}]}\n' "$service" > "$WORK/trust.json"
  aws iam create-role --role-name "$name" --assume-role-policy-document "file://$WORK/trust.json" \
    --query Role.Arn --output text
  for policy in "$@"; do
    aws iam attach-role-policy --role-name "$name" --policy-arn "arn:aws:iam::aws:policy/$policy"
  done
  NEW_IAM=1
}
ensure_role eksClusterRole eks.amazonaws.com AmazonEKSClusterPolicy
ensure_role AmazonEKSNodeRole ec2.amazonaws.com \
  AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly
# An instance profile is how an EC2 machine carries an IAM role.
if ! aws iam get-instance-profile --instance-profile-name AmazonEKSNodeRole >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name AmazonEKSNodeRole \
    --query InstanceProfile.Arn --output text
  aws iam add-role-to-instance-profile --instance-profile-name AmazonEKSNodeRole --role-name AmazonEKSNodeRole
  NEW_IAM=1
fi
if [ "$NEW_IAM" = 1 ]; then
  echo "waiting 20 seconds for the new IAM objects to become usable"
  sleep 20
fi

step "4/8 EKS cluster (about 10 minutes the first time)"
# us-east-1e cannot host an EKS control plane, so it is skipped.
SUBNETS="$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true \
  --query "Subnets[?AvailabilityZone!='us-east-1e'].SubnetId | [0:3] | join(',', @)" --output text)"
if ! aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks create-cluster --name "$CLUSTER" --kubernetes-version "$K8S_VERSION" \
    --role-arn "arn:aws:iam::$ACCOUNT_ID:role/eksClusterRole" \
    --resources-vpc-config "subnetIds=$SUBNETS,endpointPublicAccess=true" \
    --query cluster.status --output text
fi
aws eks wait cluster-active --name "$CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --alias "$CONTEXT" --profile "$AWS_PROFILE" >/dev/null
echo "cluster is ACTIVE; kubectl now points at $CONTEXT"

step "5/8 Nodes"
# The sandbox blocks managed node groups, so the nodes are plain EC2 machines
# that are told how to join. This entry lets machines with the node role in.
cat > "$WORK/aws-auth.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKSNodeRole
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
k apply -f "$WORK/aws-auth.yaml"

SG="$(aws eks describe-cluster --name "$CLUSTER" --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)"
RUNNING="$(aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" Name=instance-state-name,Values=running,pending \
  --query 'length(Reservations[].Instances[])' --output text)"
MISSING=$((NODE_COUNT - RUNNING))
if [ "$MISSING" -gt 0 ]; then
  ENDPOINT="$(aws eks describe-cluster --name "$CLUSTER" --query cluster.endpoint --output text)"
  CA="$(aws eks describe-cluster --name "$CLUSTER" --query cluster.certificateAuthority.data --output text)"
  CIDR="$(aws eks describe-cluster --name "$CLUSTER" --query cluster.kubernetesNetworkConfig.serviceIpv4Cidr --output text)"
  AMI="$(aws ec2 describe-images --owners 602401143452 \
    --filters "Name=name,Values=amazon-eks-node-al2023-x86_64-standard-$K8S_VERSION-v*" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
  cat > "$WORK/userdata.txt" <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${CLUSTER}
    apiServerEndpoint: ${ENDPOINT}
    certificateAuthority: ${CA}
    cidr: ${CIDR}

--BOUNDARY--
EOF
  echo "launching $MISSING node(s) from image $AMI"
  aws ec2 run-instances --image-id "$AMI" --instance-type "$NODE_TYPE" --count "$MISSING" \
    --subnet-id "${SUBNETS%%,*}" --security-group-ids "$SG" \
    --iam-instance-profile Name=AmazonEKSNodeRole \
    --user-data "file://$WORK/userdata.txt" \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp2,DeleteOnTermination=true}' \
    --metadata-options HttpTokens=required,HttpPutResponseHopLimit=2 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTER-node},{Key=kubernetes.io/cluster/$CLUSTER,Value=owned}]" \
    --query 'Instances[].InstanceId' --output text
else
  echo "$RUNNING node(s) already running"
fi

echo "waiting for $NODE_COUNT nodes to be Ready"
READY=0
for _ in $(seq 1 60); do
  READY="$(k get nodes --no-headers 2>/dev/null | grep -cw Ready || true)"
  if [ "$READY" -ge "$NODE_COUNT" ]; then break; fi
  sleep 10
done
k get nodes
if [ "$READY" -lt "$NODE_COUNT" ]; then
  echo "the nodes did not become Ready within 10 minutes" >&2
  exit 1
fi

step "6/8 Namespace, secret and migration files"
k apply -f kubernetes/namespace.yaml
if ! k -n "$NAMESPACE" get secret db-credentials >/dev/null 2>&1; then
  # The password is generated here and never printed or written to disk.
  k -n "$NAMESPACE" create secret generic db-credentials \
    --from-literal=POSTGRES_DB=devops_app --from-literal=POSTGRES_USER=devops_app \
    --from-literal="POSTGRES_PASSWORD=$(openssl rand -hex 16)"
fi
k -n "$NAMESPACE" create configmap migrations --from-file=app/migrations --dry-run=client -o yaml | k apply -f -

step "7/8 Deploy the chart"
helm upgrade --install devops-app "$CHART" --kube-context "$CONTEXT" -n "$NAMESPACE" \
  -f "$CHART/values-eks.yaml" \
  --set "image.repository=$ECR/devops-app" --set "image.tag=$TAG" --timeout 8m
k -n "$NAMESPACE" rollout status deployment/devops-app --timeout=5m

step "8/8 Open the app's port"
if [ -z "$ALLOW_CIDR" ]; then
  ALLOW_CIDR="$(curl -s https://checkip.amazonaws.com)/32"
fi
if aws ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp \
  --port "$NODE_PORT" --cidr "$ALLOW_CIDR" >/dev/null 2>&1; then
  echo "port $NODE_PORT opened for $ALLOW_CIDR"
else
  echo "port $NODE_PORT was already open for $ALLOW_CIDR, or the rule was refused"
fi

echo
echo "The app is up. Open either address:"
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text | tr '\t' '\n' \
  | sed "s|^|  http://|; s|\$|:$NODE_PORT|"
echo
echo "Check it with scripts/aws-status.sh, and stop everything with scripts/aws-down.sh"
