#!/usr/bin/env bash
# Deploys the app onto the cluster that Terraform built:
# copies the image into the registry, points kubectl at the cluster, installs the chart.
#
# Usage:  export AWS_PROFILE=kk
#         scripts/aws-deploy.sh [image-tag]
#
# Safe to run again: every step first checks whether its work is already done.
set -euo pipefail

# Git Bash rewrites arguments that look like Unix paths. Switch that off.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" AWS_PAGER=""
: "${AWS_PROFILE:?Set AWS_PROFILE first, for example: export AWS_PROFILE=kk}"

NAMESPACE="devops-app"
CONTEXT="eks-devops-app"
CHART="kubernetes/helm/devops-app"
TF_DIR="terraform/environments/sandbox"

cd "$(dirname "$0")/.."

step() { echo; echo "==> $*"; }
k() { kubectl --context "$CONTEXT" "$@"; }
tf_output() { terraform -chdir="$TF_DIR" output -raw "$1"; }

step "1/5 What did Terraform build?"
ECR_URL="$(tf_output registry_url)"
CLUSTER="$(tf_output cluster_name)"
NODE_COUNT="$(tf_output node_count)"
AWS_REGION="$(tf_output region)"
export AWS_REGION
git fetch --quiet origin develop
TAG="${1:-sha-$(git rev-parse --short origin/develop)}"
echo "registry $ECR_URL, cluster $CLUSTER, image tag $TAG"

step "2/5 Copy the image into the registry"
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%%/*}" >/dev/null
if aws ecr describe-images --repository-name "${ECR_URL#*/}" --image-ids "imageTag=$TAG" >/dev/null 2>&1; then
  echo "image $TAG is already in the registry"
else
  # Copy, never rebuild: the digest in ECR is the one CI scanned and signed.
  docker buildx imagetools create --tag "$ECR_URL:$TAG" "ghcr.io/balamahanth2/devops-app:$TAG"
fi

step "3/5 Point kubectl at the cluster and wait for the nodes"
aws eks update-kubeconfig --name "$CLUSTER" --alias "$CONTEXT" --profile "$AWS_PROFILE" >/dev/null
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

step "4/5 Namespace, secret and migration files"
k apply -f kubernetes/namespace.yaml
if ! k -n "$NAMESPACE" get secret db-credentials >/dev/null 2>&1; then
  # The password is generated here and never printed or written to disk.
  k -n "$NAMESPACE" create secret generic db-credentials \
    --from-literal=POSTGRES_DB=devops_app --from-literal=POSTGRES_USER=devops_app \
    --from-literal="POSTGRES_PASSWORD=$(openssl rand -hex 16)"
fi
k -n "$NAMESPACE" create configmap migrations --from-file=app/migrations --dry-run=client -o yaml | k apply -f -

step "5/5 Deploy the chart"
helm upgrade --install devops-app "$CHART" --kube-context "$CONTEXT" -n "$NAMESPACE" \
  -f "$CHART/values-eks.yaml" \
  --set "image.repository=$ECR_URL" --set "image.tag=$TAG" --timeout 8m
k -n "$NAMESPACE" rollout status deployment/devops-app --timeout=5m

echo
echo "The app is up. Open either address:"
terraform -chdir="$TF_DIR" output -json app_urls | tr -d '[]" ' | tr ',' '\n' | sed 's/^/  /'
echo
echo "Check it with scripts/aws-status.sh, and stop everything with: terraform destroy"
