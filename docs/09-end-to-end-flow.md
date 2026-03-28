# 09 — End-to-End Flow

## The Complete Journey: Code Change → Live Traffic

This document walks through exactly what happens when you make a code change and push it.

---

## Step 1: You change code and push

```bash
# Make a change to the app
echo "// new feature" >> cicd-k8s-project/app/src/index.js

git add cicd-k8s-project/app/src/index.js
git commit -m "feat: add new endpoint"
git push origin main
```

**What happens on GitHub's side:**
- GitHub receives the push
- Scans `.github/workflows/` for workflows triggered by `push` to `main`
- Finds `ci.yml` — and checks if `app/**` files changed → YES → queues the CI job

---

## Step 2: CI Job 1 — Tests (runs on a GitHub Ubuntu VM)

```
[Runner] ubuntu-latest VM boots (fresh, clean)
    ↓
actions/checkout@v4
  → git clone your repo into /home/runner/work/...
    ↓
actions/setup-node@v4
  → installs Node.js 20 on the runner
    ↓
npm ci
  → installs express, jest, supertest from package-lock.json
    ↓
npm test -- --ci --forceExit
  → Jest runs app.test.js
  → 5 tests execute (health, root, items list, single item, 404)
```

**If any test fails:**
```
❌ Test failed → job exits with code 1 → CI marked FAILED
→ build-and-push job is SKIPPED
→ CD workflow never triggers
→ Nothing is deployed. Your cluster still runs the old version.
```

**If all tests pass:**
```
✅ All 5 tests pass → job exits with code 0 → triggers next job
```

---

## Step 3: CI Job 2 — Build & Push (runs on another fresh VM)

```
[Runner] ubuntu-latest VM boots
    ↓
actions/checkout@v4
  → clone repo
    ↓
aws-actions/configure-aws-credentials@v4
  → reads secrets.AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  → configures AWS CLI on the runner
    ↓
aws-actions/amazon-ecr-login@v2
  → runs: aws ecr get-login-password | docker login <ECR_URI>
  → Docker is now authenticated to push to your ECR
    ↓
docker/setup-buildx-action@v3
  → enables advanced Docker build features + GHA cache
    ↓
docker/build-push-action@v5
  → docker build ./app (multi-stage Dockerfile)
  → Stage 1 (builder): npm ci --only=production
  → Stage 2 (runtime): copy node_modules + src, set non-root user
  → docker push <ECR_URI>/cicd-demo-app:abc123def  (commit SHA)
  → docker push <ECR_URI>/cicd-demo-app:latest
    ↓
aquasecurity/trivy-action
  → scans the pushed image for HIGH/CRITICAL CVEs
  → prints report to logs (exit-code=0 so doesn't fail the build)
```

At the end of this step, your ECR has a new image tagged with the exact commit SHA.

---

## Step 4: CD Workflow Triggers

The CD workflow is listening for `workflow_run: completed` of the CI workflow.

```
CI workflow finishes (conclusion: success)
    ↓
GitHub queues the CD workflow
    ↓
Checks: github.event.workflow_run.conclusion == 'success' → YES
    ↓
CD job starts on a fresh runner
```

---

## Step 5: CD — Update Helm values

```
[Runner] boots
    ↓
checkout + AWS credentials (same as CI)
    ↓
ECR login (to get registry URL)
    ↓
aws eks update-kubeconfig --name cicd-demo-cluster --region ap-south-1
  → writes ~/.kube/config on the runner
  → runner can now run kubectl commands against your EKS cluster
    ↓
sed -i "s|tag:.*|tag: \"abc123def\"|" helm/cicd-demo-app/values.yaml
  → opens values.yaml, finds the line starting with "tag:"
  → replaces it with the new commit SHA tag
    ↓
git config user.name "github-actions[bot]"
git add helm/cicd-demo-app/values.yaml
git commit -m "chore: deploy image tag abc123def [skip ci]"
git push
  → this commit goes to your main branch
  → [skip ci] prevents CI from triggering again
```

Your git log now has a deployment record:
```
abc123def  feat: add new endpoint          ← your change
58e73af1   chore: deploy image tag abc123  ← automated deployment commit
```

---

## Step 6: ArgoCD Detects the Change

```
ArgoCD polls Git every 3 minutes
    ↓
Detects: helm/cicd-demo-app/values.yaml changed
    ↓
Compares: what's in Git vs what's running in the cluster
    ↓
Difference found: image tag is different
    ↓
Status changes to: OutOfSync
    ↓
(if automated sync enabled) → triggers sync immediately
```

OR the CD workflow manually triggers it:
```bash
argocd app sync cicd-demo-app --timeout 120
```

---

## Step 7: ArgoCD Syncs the Cluster

```
ArgoCD runs: helm template cicd-demo-app ./helm/cicd-demo-app
  → generates the Kubernetes YAML with new image tag
    ↓
ArgoCD applies the generated manifests to the cluster
  → equivalent to: kubectl apply -f <all the generated YAMLs>
    ↓
Kubernetes sees the Deployment has changed (new image tag)
    ↓
Kubernetes controller starts a RollingUpdate
```

---

## Step 8: Kubernetes Rolling Update

```
Current state: 2 pods running old image
    ↓
Kubernetes starts 1 new pod (maxSurge: 1 → temporarily 3 pods total)
    ↓
New pod pulls image from ECR: <ECR_URI>/cicd-demo-app:abc123def
    ↓
readinessProbe: GET /health → waits for 200 response
    ↓ (10 seconds, app has started)
New pod is Ready ✓
    ↓
Kubernetes terminates 1 old pod (now 2 pods again: 1 old + 1 new)
    ↓
Kubernetes starts 2nd new pod
    ↓
readinessProbe passes ✓
    ↓
Kubernetes terminates last old pod
    ↓
Final state: 2 pods running new image ✓
```

**Zero downtime throughout** — the Service always has ready pods to route traffic to.
Traffic was never interrupted.

---

## Step 9: Traffic flows through the NLB

```
User → http://<NLB-HOSTNAME>/api/items
    ↓
AWS Network Load Balancer
  → TCP connection to one of the healthy pods
    ↓
Node.js Express app handles the request
    ↓
Response → NLB → User
```

The NLB automatically removes pods from rotation when their readiness probe fails,
and adds them back when it passes. This is managed by the Kubernetes Service.

---

## What the traffic test script checks

```bash
bash scripts/test-traffic.sh
```

1. Gets the NLB hostname from kubectl
2. Tests all endpoints (`/`, `/health`, `/api/items`, `/api/items/1`, `/api/items/99`)
3. Runs 10 consecutive requests to `/health` (load test)
4. Shows pod status and deployment status

---

## Rollback scenario

If the new version has a bug and pods are crashing:

**Option A: Git revert (GitOps way)**
```bash
git revert HEAD    # reverts the values.yaml commit
git push
# ArgoCD detects the revert → deploys previous image tag
```

**Option B: ArgoCD rollback**
```bash
argocd app history cicd-demo-app   # see deployment history
argocd app rollback cicd-demo-app 3   # roll back to revision 3
```

**Option C: Helm rollback**
```bash
helm history cicd-demo-app -n cicd-demo
helm rollback cicd-demo-app -n cicd-demo   # previous version
```

Option A is the GitOps-correct approach because it keeps Git as the source of truth.

---

## Summary timeline for a typical deployment

```
0:00  git push
0:05  CI starts (checkout, npm ci)
0:45  Tests pass
1:00  Docker build starts
2:30  Image pushed to ECR
2:35  Trivy scan completes
2:40  CD workflow starts
3:00  values.yaml updated, committed, pushed
3:03  ArgoCD detects change (next poll)
3:10  Helm upgrade starts
3:30  First new pod ready
3:50  Second new pod ready, old pods terminated
4:00  Deployment complete — new version live
```

Total: ~4 minutes from `git push` to live deployment.
