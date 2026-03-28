# 03 — GitHub Actions CI

## What is CI?

**Continuous Integration** — every time you push code, an automated system:
1. Pulls your code
2. Installs dependencies
3. Runs tests
4. Builds a Docker image
5. Pushes it to a registry

The goal: catch broken code before it reaches your cluster.

---

## File: `.github/workflows/ci.yml`

GitHub automatically looks in `.github/workflows/` for workflow files.
Any `.yml` file there is treated as a workflow.

---

### Trigger

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - 'app/**'
      - '.github/workflows/ci.yml'
  pull_request:
    branches: [main]
    paths:
      - 'app/**'
```

- `on:` defines **when** the workflow runs
- `push` — triggers on git push
- `branches: [main, develop]` — only for these branches (not feature branches)
- `paths:` — only triggers if files matching these patterns changed
  - If you only change Terraform files, this CI doesn't run (saves GitHub Actions minutes)
- `pull_request` — also runs on PRs to main, but in read-only mode (no ECR push)

---

### Environment variables

```yaml
env:
  AWS_REGION: ap-south-1
  ECR_REPOSITORY: cicd-demo-app
  IMAGE_TAG: ${{ github.sha }}
```

- `env:` at the top level makes these available to all jobs
- `${{ github.sha }}` — the full git commit SHA (e.g. `a3f8c2d1...`)
  - Used as the Docker image tag so every image maps to an exact commit
  - You can always trace a running container back to its source code

---

### Job 1: Test

```yaml
jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest
```

- `jobs:` — a workflow has one or more jobs, each runs on its own machine
- `runs-on: ubuntu-latest` — GitHub spins up a fresh Ubuntu VM for this job
  - Fresh VM every time = no state pollution between runs

```yaml
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
```

- `steps:` — ordered list of things to do
- `uses:` — runs a **pre-built Action** from GitHub Marketplace
- `actions/checkout@v4` — clones your repository onto the runner VM
  - Without this, the runner has an empty machine with no code

```yaml
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: app/package-lock.json
```

- `actions/setup-node@v4` — installs the specified Node.js version on the runner
- `cache: 'npm'` — caches the npm cache between runs; if dependencies haven't changed, skips download
- `cache-dependency-path` — which file to check for cache invalidation

```yaml
      - name: Install dependencies
        working-directory: app
        run: npm ci
```

- `working-directory: app` — run this command inside the `app/` folder
- `run:` — runs a shell command directly
- `npm ci` — installs exact versions from `package-lock.json`

```yaml
      - name: Run tests with coverage
        working-directory: app
        run: npm test -- --ci --forceExit
```

- `--ci` — Jest CI mode: no watch, fails immediately on first test suite failure
- `--forceExit` — force Jest to exit after tests (prevents hanging on open handles)
- If any test fails → this step exits with code 1 → **job fails → build-and-push job never runs**

```yaml
      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report
          path: app/coverage/
          retention-days: 7
```

- `uses: actions/upload-artifact@v4` — saves files from the runner so you can download them
- `if: always()` — upload even if tests failed (so you can see the partial coverage report)
- `retention-days: 7` — GitHub deletes the artifact after 7 days

---

### Job 2: Build and Push

```yaml
  build-and-push:
    needs: test
    if: github.event_name == 'push'
```

- `needs: test` — **this job only starts after `test` job succeeds**
  - If tests fail, this job never runs — broken code never reaches ECR
- `if: github.event_name == 'push'` — don't push images on pull requests
  - PRs from forks could be malicious; we don't want them writing to our ECR

```yaml
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
```

- `${{ secrets.AWS_ACCESS_KEY_ID }}` — reads from **GitHub Secrets**
  - Set at: GitHub repo → Settings → Secrets and variables → Actions
  - Secrets are encrypted and never appear in logs
- This step configures the AWS CLI and SDKs used by subsequent steps

```yaml
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2
```

- Authenticates Docker to ECR (runs the `aws ecr get-login-password | docker login ...` command)
- `id: login-ecr` — names this step so its outputs can be referenced later
- This step outputs `registry` = your ECR registry URL

```yaml
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
```

- Buildx is an extended Docker build tool
- Enables build caching with `--cache-from type=gha` (GitHub Actions cache)
- Also enables multi-platform builds if needed

```yaml
      - name: Build and push to ECR
        uses: docker/build-push-action@v5
        with:
          context: ./app
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/cicd-demo-app:${{ env.IMAGE_TAG }}
            ${{ steps.login-ecr.outputs.registry }}/cicd-demo-app:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- `context: ./app` — Docker build context (where the Dockerfile is)
- `push: true` — actually push after building
- `tags:` — push with two tags:
  - `:abc123def` (commit SHA) — immutable, for traceability
  - `:latest` — always points to the most recent push
- `cache-from/cache-to: type=gha` — GitHub Actions cache; layers are reused between runs

```yaml
      - name: Image scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: <ECR_URI>/cicd-demo-app:${{ env.IMAGE_TAG }}
          format: 'table'
          exit-code: '0'
          severity: 'HIGH,CRITICAL'
```

- **Trivy** scans the Docker image for known CVEs (Common Vulnerabilities and Exposures)
- `severity: 'HIGH,CRITICAL'` — only report high and critical issues
- `exit-code: '0'` — report but don't fail the build. Change to `'1'` to enforce no HIGH/CRITICAL vulns

---

## Reading Workflow Logs

Go to: `GitHub repo → Actions tab → click a workflow run`

Each job is shown separately. Click into a job to see each step's output.
Red = failed. Yellow = skipped. Green = passed.

---

## GitHub Secrets Setup

Before CI/CD works, add these in GitHub:

```
GitHub repo → Settings → Secrets and variables → Actions → New repository secret
```

| Secret Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your IAM user's access key ID |
| `AWS_SECRET_ACCESS_KEY` | Your IAM user's secret key |
| `ARGOCD_ADMIN_PASSWORD` | ArgoCD admin password (set after install) |

The IAM user needs these permissions:
- `AmazonEC2ContainerRegistryPowerUser` — push/pull ECR images
- `AmazonEKSClusterPolicy` — update kubeconfig, deploy to EKS
