#!/bin/bash
# ──────────────────────────────────────────────────────
# Install AWS Load Balancer Controller on EKS
# Requires: helm, kubectl, aws CLI configured
# ──────────────────────────────────────────────────────
set -euo pipefail

CLUSTER_NAME="${1:-cicd-demo-cluster}"
AWS_REGION="${2:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LB_CONTROLLER_ROLE_ARN="${3:-}"  # Pass from terraform output

echo "==> Installing AWS Load Balancer Controller"
echo "    Cluster:    $CLUSTER_NAME"
echo "    Region:     $AWS_REGION"
echo "    Account ID: $AWS_ACCOUNT_ID"

# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LB_CONTROLLER_ROLE_ARN" \
  --set region="$AWS_REGION" \
  --set vpcId="$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION \
      --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

echo "==> Waiting for LB controller pods..."
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
echo "==> AWS Load Balancer Controller installed successfully!"
