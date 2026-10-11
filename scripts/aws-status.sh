#!/usr/bin/env bash
# Shows the state of the app on AWS: cluster, nodes, pods, warnings, addresses, health.
# It only reads; it changes nothing.
#
# Usage:  export AWS_PROFILE=kk
#         scripts/aws-status.sh
set -uo pipefail

export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" AWS_PAGER=""
export AWS_REGION="${AWS_REGION:-us-east-1}"
: "${AWS_PROFILE:?Set AWS_PROFILE first, for example: export AWS_PROFILE=kk}"

CLUSTER="devops-app"
NODE_PORT=30080
NAMESPACE="devops-app"
CONTEXT="eks-devops-app"

step() { echo; echo "==> $*"; }
k() { kubectl --context "$CONTEXT" "$@"; }

step "Account"
if ! aws sts get-caller-identity --query Arn --output text; then
  echo "These credentials do not work. Has the sandbox expired?" >&2
  exit 1
fi

step "Cluster"
STATUS="$(aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text 2>/dev/null)"
if [ -z "$STATUS" ]; then
  echo "There is no cluster named $CLUSTER. Start one with scripts/aws-up.sh"
  exit 0
fi
echo "$CLUSTER is $STATUS"

step "Nodes"
k get nodes -o wide

step "Pods"
k -n "$NAMESPACE" get pods -o wide

step "Recent warnings"
k -n "$NAMESPACE" get events --field-selector type=Warning --sort-by=.lastTimestamp | tail -8

step "Addresses and health"
IPS="$(aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text | tr '\t' '\n')"
for ip in $IPS; do
  health="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$ip:$NODE_PORT/health")"
  ready="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$ip:$NODE_PORT/ready")"
  echo "http://$ip:$NODE_PORT   health=$health ready=$ready"
done
echo "(000 means no answer: the port is not open for the network you are on)"

step "Last log lines of the app"
k -n "$NAMESPACE" logs deploy/devops-app --tail=8
