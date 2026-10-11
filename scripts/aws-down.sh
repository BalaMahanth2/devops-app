#!/usr/bin/env bash
# Stops everything scripts/aws-up.sh started, in the order that leaves nothing behind.
# A step that finds nothing to delete is skipped, so it is safe to run twice.
#
# Usage:  export AWS_PROFILE=kk
#         scripts/aws-down.sh
set -uo pipefail

export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" AWS_PAGER=""
export AWS_REGION="${AWS_REGION:-us-east-1}"
: "${AWS_PROFILE:?Set AWS_PROFILE first, for example: export AWS_PROFILE=kk}"

CLUSTER="devops-app"
NAMESPACE="devops-app"
CONTEXT="eks-devops-app"

step() { echo; echo "==> $*"; }

step "1/6 Remove the app"
if kubectl config get-contexts -o name | grep -qx "$CONTEXT"; then
  helm uninstall devops-app --kube-context "$CONTEXT" -n "$NAMESPACE" --wait --timeout 3m || true
  kubectl --context "$CONTEXT" delete namespace "$NAMESPACE" --ignore-not-found --timeout=3m || true
else
  echo "no kubectl context named $CONTEXT, skipping"
fi

step "2/6 Terminate the nodes"
IDS="$(aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" Name=instance-state-name,Values=running,pending,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text)"
if [ -n "$IDS" ]; then
  # shellcheck disable=SC2086  # the IDs must be passed as separate arguments
  aws ec2 terminate-instances --instance-ids $IDS --query 'TerminatingInstances[].InstanceId' --output text
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $IDS && echo "nodes terminated"
else
  echo "no nodes running"
fi

step "3/6 Delete the cluster (a few minutes)"
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks delete-cluster --name "$CLUSTER" --query cluster.status --output text
  aws eks wait cluster-deleted --name "$CLUSTER" && echo "cluster deleted"
else
  echo "no cluster named $CLUSTER"
fi

step "4/6 Delete the registry"
if aws ecr describe-repositories --repository-names devops-app >/dev/null 2>&1; then
  aws ecr delete-repository --repository-name devops-app --force --query repository.repositoryName --output text
else
  echo "no registry named devops-app"
fi

step "5/6 Delete the IAM roles"
if aws iam get-instance-profile --instance-profile-name AmazonEKSNodeRole >/dev/null 2>&1; then
  aws iam remove-role-from-instance-profile --instance-profile-name AmazonEKSNodeRole --role-name AmazonEKSNodeRole || true
  aws iam delete-instance-profile --instance-profile-name AmazonEKSNodeRole
fi
for role in eksClusterRole AmazonEKSNodeRole; do
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    for arn in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text); do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$arn"
    done
    aws iam delete-role --role-name "$role" && echo "role $role deleted"
  fi
done

step "6/6 Point kubectl back at the local cluster"
if kubectl config get-contexts -o name | grep -qx "kind-devops-app"; then
  kubectl config use-context kind-devops-app
fi
kubectl config delete-context "$CONTEXT" >/dev/null 2>&1 && echo "removed context $CONTEXT"

echo
echo "Everything is stopped."
