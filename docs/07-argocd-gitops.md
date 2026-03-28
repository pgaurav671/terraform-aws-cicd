# 07 — ArgoCD & GitOps

## What is GitOps?

GitOps is a deployment practice where **Git is the single source of truth** for
what should be running in your cluster.

Traditional deployment:
```
Developer → runs 'kubectl apply' or 'helm upgrade' → cluster changes
```

GitOps:
```
Developer → commits to Git → ArgoCD detects change → ArgoCD applies to cluster
```

The cluster state always matches what's in Git. No one manually touches the cluster.

---

## What is ArgoCD?

ArgoCD is a **GitOps controller** that runs inside your Kubernetes cluster.

It continuously:
1. Watches a Git repository (your Helm chart + values.yaml)
2. Compares what's in Git vs what's running in the cluster
3. If they differ → syncs the cluster to match Git

---

## File: `argocd/argocd-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-demo-app
  namespace: argocd
```

- This is a **custom Kubernetes resource** added by ArgoCD
- Lives in the `argocd` namespace (where ArgoCD itself runs)
- `name: cicd-demo-app` — this is the ArgoCD application name you see in the UI

### Source section

```yaml
spec:
  source:
    repoURL: https://github.com/pgaurav671/terraform-aws-cicd.git
    targetRevision: HEAD
    path: cicd-k8s-project/helm/cicd-demo-app

    helm:
      valueFiles:
        - values.yaml
```

- `repoURL` — the Git repo ArgoCD watches
- `targetRevision: HEAD` — always track the latest commit on the default branch
- `path` — the folder inside the repo that contains the Helm chart
- `helm.valueFiles` — which values file(s) to use

### Destination section

```yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: cicd-demo
```

- `https://kubernetes.default.svc` — the local cluster (where ArgoCD is running)
- `namespace: cicd-demo` — deploy the app into this namespace

### Sync policy

```yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

- `automated:` — ArgoCD syncs automatically without manual trigger
- `prune: true` — if you remove a resource from the Helm chart, ArgoCD DELETES it from the cluster
  - Without prune, old resources pile up
- `selfHeal: true` — if someone manually changes something in the cluster (e.g. `kubectl edit`),
  ArgoCD detects the drift and reverts it back to what Git says
- `CreateNamespace=true` — create the namespace if it doesn't exist
- `retry.limit: 5` — retry failed syncs up to 5 times
- `backoff` — exponential backoff: 5s, 10s, 20s, 40s, 80s between retries

---

## File: `argocd/install-argocd.sh`

### Step by step

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
```
- `--dry-run=client -o yaml` generates the YAML without applying it
- Piping to `kubectl apply -f -` applies it
- This pattern is idempotent — safe to run even if namespace already exists

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
- Installs all ArgoCD components: server, repo-server, application-controller, redis, dex
- `stable` — latest stable release

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'
```
- Changes the ArgoCD server service from `ClusterIP` (internal only) to `LoadBalancer`
- This creates an AWS NLB and gives you a public URL to access the ArgoCD UI

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
```
- ArgoCD stores the initial admin password as a base64-encoded Kubernetes secret
- `-o jsonpath="{.data.password}"` — extract just the password field
- `| base64 -d` — decode from base64 to plain text

---

## ArgoCD CLI Commands

```bash
# Login to ArgoCD
argocd login <ARGOCD_URL> --username admin --password <PASSWORD>

# Login insecure (no TLS cert validation — for self-signed certs)
argocd login <URL> --username admin --password <PASSWORD> --insecure

# List all applications
argocd app list

# Get application details and sync status
argocd app get cicd-demo-app

# Manually trigger a sync (check Git now, don't wait for polling)
argocd app sync cicd-demo-app

# Wait until app is healthy
argocd app wait cicd-demo-app --health

# Wait until app is synced
argocd app wait cicd-demo-app --sync

# See sync history
argocd app history cicd-demo-app

# Roll back to a previous sync (by history ID)
argocd app rollback cicd-demo-app <ID>

# Delete an application (does NOT delete K8s resources unless --cascade)
argocd app delete cicd-demo-app
argocd app delete cicd-demo-app --cascade   # also deletes K8s resources

# Change admin password
argocd account update-password

# Add a private Git repo
argocd repo add https://github.com/user/private-repo \
  --username <user> --password <token>
```

---

## ArgoCD Application States

| State | Meaning |
|---|---|
| `Synced` | Cluster matches Git |
| `OutOfSync` | Git changed, cluster not yet updated |
| `Progressing` | Sync is in progress |
| `Healthy` | All pods running and ready |
| `Degraded` | Some pods crashing or not ready |
| `Missing` | Resources defined in Git don't exist in cluster |
| `Unknown` | Can't determine health |

You always want: **Synced + Healthy**

---

## How ArgoCD Detects Changes

1. **Polling** (default) — ArgoCD checks the Git repo every 3 minutes
2. **Webhook** — GitHub notifies ArgoCD immediately on push (faster, requires setup)

To set up webhook in GitHub:
```
GitHub repo → Settings → Webhooks → Add webhook
Payload URL: https://<ARGOCD_URL>/api/webhook
Content type: application/json
Events: Push events
```

---

## ArgoCD UI

After installation:
1. Get the URL: `kubectl get svc argocd-server -n argocd`
2. Open `https://<EXTERNAL_HOSTNAME>` in your browser
3. Login: username `admin`, password from the secret

In the UI you can:
- See all applications and their sync/health status
- View resource tree (Deployment → ReplicaSet → Pods)
- See diff between Git and cluster
- Manually trigger syncs
- View logs and events
- Roll back deployments

---

## GitOps Workflow Summary

```
1. Developer: git push to main
       ↓
2. CI: tests pass → image pushed to ECR (tagged with SHA)
       ↓
3. CD: updates helm/values.yaml → git commit [skip ci] → git push
       ↓
4. ArgoCD: detects values.yaml changed (polling or webhook)
       ↓
5. ArgoCD: runs helm upgrade with new values
       ↓
6. Kubernetes: rolling update — new pods start, old pods terminate
       ↓
7. ArgoCD: reports Synced + Healthy
       ↓
8. Traffic flows to new pods via NLB
```

If step 6 fails (pods crash, readiness probe fails):
- Kubernetes stops the rolling update
- Old pods keep running (zero downtime)
- ArgoCD reports `Degraded`
- You fix the code → push again → restarts the process
