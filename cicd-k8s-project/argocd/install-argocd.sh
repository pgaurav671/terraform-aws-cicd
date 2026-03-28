#!/bin/bash
# ──────────────────────────────────────────────────────
# Install ArgoCD on EKS and expose via LoadBalancer
# Run this ONCE after EKS cluster is ready
# ──────────────────────────────────────────────────────
set -euo pipefail

CLUSTER_NAME="${1:-cicd-demo-cluster}"
AWS_REGION="${2:-us-east-1}"

echo "==> Configuring kubectl for EKS cluster: $CLUSTER_NAME"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo "==> Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD"
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD pods to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

echo "==> Patching ArgoCD server service to LoadBalancer"
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "==> Waiting for LoadBalancer hostname..."
for i in $(seq 1 30); do
  HOSTNAME=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$HOSTNAME" ]; then
    echo "ArgoCD UI available at: https://$HOSTNAME"
    break
  fi
  echo "  Still waiting... ($i/30)"
  sleep 10
done

echo "==> Getting initial ArgoCD admin password"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"
echo ""
echo "IMPORTANT: Change this password immediately after first login!"
echo "  argocd login $HOSTNAME --username admin --password $ARGOCD_PASSWORD"
echo "  argocd account update-password"

echo "==> Applying ArgoCD Application manifest"
kubectl apply -f "$(dirname "$0")/argocd-app.yaml"

echo ""
echo "==> ArgoCD installation complete!"
echo "    UI:       https://$HOSTNAME"
echo "    Username: admin"
echo "    Password: $ARGOCD_PASSWORD"
