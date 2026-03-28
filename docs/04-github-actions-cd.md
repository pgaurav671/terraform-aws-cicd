# 04 — GitHub Actions CD

## What is CD?

**Continuous Deployment** — once CI has built and pushed a verified image,
CD automatically deploys it to the cluster.

Our CD approach is **GitOps**: instead of running `kubectl apply` or `helm upgrade`
directly, the CD workflow updates a file in Git. ArgoCD watches Git and deploys
whatever is there. Git is always the source of truth.

---

## File: `.github/workflows/cd.yml`

### Trigger

```yaml
on:
  workflow_run:
    workflows: ["CI - Build, Test & Push"]
    types: [completed]
    branches: [main]
```

- `workflow_run` — triggers when another workflow finishes
- This CD workflow runs **after the CI workflow completes**
- It does NOT trigger directly on `git push` — CI must pass first

```yaml
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
```

- Additional guard: only deploy if CI actually **succeeded**
- If CI failed (tests broke, build error), this condition is false and CD never runs

---

### Step: Get image tag

```yaml
      - name: Get image tag from CI run
        id: get-tag
        run: |
          TAG=${{ github.event.workflow_run.head_sha }}
          echo "image_tag=${TAG}" >> $GITHUB_OUTPUT
```

- `github.event.workflow_run.head_sha` — the commit SHA from the CI run that triggered this
- `$GITHUB_OUTPUT` — a special file; writing `key=value` here makes it available
  to later steps as `${{ steps.get-tag.outputs.image_tag }}`

---

### Step: Update kubeconfig

```yaml
      - name: Update kubeconfig for EKS
        run: |
          aws eks update-kubeconfig \
            --name ${{ env.EKS_CLUSTER_NAME }} \
            --region ${{ env.AWS_REGION }}
```

- Downloads the kubeconfig for the EKS cluster to `~/.kube/config` on the runner
- After this, `kubectl` commands on the runner talk to your EKS cluster
- Think of it as "logging in to Kubernetes"

---

### Step: Update Helm values (the GitOps part)

```yaml
      - name: Update Helm values with new image tag
        run: |
          TAG=${{ steps.get-tag.outputs.image_tag }}
          REGISTRY=${{ steps.login-ecr.outputs.registry }}

          sed -i "s|tag:.*|tag: \"${TAG}\"|" helm/cicd-demo-app/values.yaml
          sed -i "s|repository:.*|repository: ${REGISTRY}/cicd-demo-app|" helm/cicd-demo-app/values.yaml
```

- `sed -i "s|old|new|" file` — find and replace in a file, in-place
- `s|tag:.*|tag: "abc123"|` — replaces the entire `tag:` line with the new value
- After this, `values.yaml` has the new image tag pointing to the just-built image

---

### Step: Commit back to Git

```yaml
      - name: Commit and push updated values
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add helm/cicd-demo-app/values.yaml
          git commit -m "chore: deploy image tag ${{ steps.get-tag.outputs.image_tag }} [skip ci]"
          git push
```

- The workflow commits the updated `values.yaml` back to the repo
- `[skip ci]` in the commit message — this tells GitHub Actions to NOT trigger CI again
  (otherwise you'd get an infinite loop: push → CI → CD commits → CI → CD → ...)
- This commit is the **deployment record** — you can see every deployment in git history

---

### Step: Trigger ArgoCD sync

```yaml
      - name: Trigger ArgoCD sync
        run: |
          kubectl port-forward svc/argocd-server -n argocd 8080:443 &
          sleep 5
          argocd login localhost:8080 \
            --username admin \
            --password ${{ secrets.ARGOCD_ADMIN_PASSWORD }} \
            --insecure
          argocd app sync cicd-demo-app --timeout 120
          argocd app wait cicd-demo-app --health --timeout 300
```

- `kubectl port-forward` — forwards local port 8080 to ArgoCD's port 443 inside the cluster
  - The `&` runs it in the background; `sleep 5` waits for it to be ready
- `argocd login` — authenticates to the ArgoCD API server
- `argocd app sync` — tells ArgoCD "check Git now, don't wait for polling interval"
- `argocd app wait --health` — blocks until the deployment is fully healthy
  - If a pod crashes, this step fails and the CD job shows as failed

---

### Step: Verify rollout

```yaml
      - name: Verify deployment rollout
        run: |
          kubectl rollout status deployment/cicd-demo-app \
            -n cicd-demo \
            --timeout=300s
```

- Waits for the Kubernetes rolling update to complete
- If pods don't become ready within 300s, this exits with failure

---

### Step: Get Load Balancer URL

```yaml
      - name: Get Load Balancer URL
        run: |
          LB_URL=$(kubectl get svc cicd-demo-app \
            -n cicd-demo \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
          echo "App deployed at: http://${LB_URL}"
```

- `kubectl get svc ... -o jsonpath='...'` — extracts a specific field from Kubernetes JSON output
- Prints the final URL to the workflow logs so you know where the app is

---

## The Complete CD Flow

```
CI workflow completes (success)
    ↓
CD workflow triggers
    ↓
Get image tag (commit SHA from CI)
    ↓
Configure AWS credentials + kubectl
    ↓
sed: update values.yaml with new tag
    ↓
git commit + git push [skip ci]
    ↓
ArgoCD detects change in Git
    ↓
ArgoCD: helm upgrade cicd-demo-app
    ↓
EKS: rolling update (zero downtime)
    ↓
kubectl rollout status → healthy ✓
    ↓
Print Load Balancer URL
```

---

## GitOps Principle

**Why update Git instead of running `helm upgrade` directly?**

| Direct deploy (`helm upgrade`) | GitOps (update Git) |
|---|---|
| Deployed state is in the cluster only | Deployed state is in Git |
| Hard to know what's actually running | `git log` shows every deployment |
| Manual rollback = run old command | Rollback = `git revert` |
| Cluster drift possible (manual kubectl) | ArgoCD reverts any drift automatically |
| No audit trail | Full audit trail in git history |

The `values.yaml` commit history IS your deployment history.
