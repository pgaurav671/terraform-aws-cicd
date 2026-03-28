#!/bin/bash
# ──────────────────────────────────────────────────────
# Traffic Test Script
# Tests the deployed app via the AWS Load Balancer
# ──────────────────────────────────────────────────────
set -euo pipefail

NAMESPACE="${1:-cicd-demo}"
APP_NAME="${2:-cicd-demo-app}"

echo "==> Getting Load Balancer URL..."
LB_URL=""
for i in $(seq 1 20); do
  LB_URL=$(kubectl get svc "$APP_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$LB_URL" ]; then
    break
  fi
  echo "  Waiting for LB... ($i/20)"
  sleep 15
done

if [ -z "$LB_URL" ]; then
  echo "ERROR: Could not get LB URL after waiting."
  exit 1
fi

BASE_URL="http://$LB_URL"
echo "==> Testing app at: $BASE_URL"
echo ""

# Helper function
check() {
  local endpoint="$1"
  local expected_status="$2"
  local description="$3"

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$endpoint")
  if [ "$HTTP_STATUS" = "$expected_status" ]; then
    echo "  PASS [$HTTP_STATUS] $description -> $endpoint"
  else
    echo "  FAIL [$HTTP_STATUS] $description -> $endpoint  (expected $expected_status)"
  fi
}

echo "── Endpoint Tests ──────────────────────────────"
check "/"           "200" "Root"
check "/health"     "200" "Health check"
check "/api/items"  "200" "Items list"
check "/api/items/1" "200" "Single item"
check "/api/items/99" "404" "Not found"

echo ""
echo "── Health Check Response ───────────────────────"
curl -s "$BASE_URL/health" | python3 -m json.tool 2>/dev/null || \
  curl -s "$BASE_URL/health"

echo ""
echo "── Load Test (10 requests) ──────────────────────"
for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
  echo "  Request $i: $STATUS"
done

echo ""
echo "── K8s Pod Status ───────────────────────────────"
kubectl get pods -n "$NAMESPACE" -o wide

echo ""
echo "── K8s Deployment Status ────────────────────────"
kubectl get deployment "$APP_NAME" -n "$NAMESPACE"

echo ""
echo "==> Traffic test complete!"
echo "    App URL: $BASE_URL"
