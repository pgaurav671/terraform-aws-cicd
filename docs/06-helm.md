# 06 — Helm

## What is Helm?

Helm is the **package manager for Kubernetes** — like apt for Ubuntu or npm for Node.js.

Without Helm, deploying an app to Kubernetes means managing many separate YAML files
(Deployment, Service, ConfigMap, HPA, etc.) and updating them manually.

With Helm, all those files are bundled into a **chart** with a single `values.yaml`
where you change things like image tag, replica count, and resource limits.

---

## Chart Structure

```
helm/cicd-demo-app/
├── Chart.yaml              ← chart metadata (name, version)
├── values.yaml             ← default configuration values
└── templates/
    ├── _helpers.tpl        ← reusable template functions
    ├── namespace.yaml      ← creates the cicd-demo namespace
    ├── serviceaccount.yaml ← Kubernetes ServiceAccount
    ├── configmap.yaml      ← non-secret config data
    ├── deployment.yaml     ← the main Deployment
    ├── service.yaml        ← the Service (Load Balancer)
    ├── hpa.yaml            ← HorizontalPodAutoscaler
    └── pdb.yaml            ← PodDisruptionBudget
```

---

## File: `Chart.yaml`

```yaml
apiVersion: v2
name: cicd-demo-app
description: CI/CD Demo Node.js Application Helm Chart
type: application
version: 0.1.0
appVersion: "1.0.0"
```

- `version` — the **chart** version (increment when you change the chart structure)
- `appVersion` — the **application** version (informational, actual tag comes from values.yaml)

---

## File: `values.yaml`

This is the main file you interact with. The CD pipeline updates `image.tag` on every deploy.

### Image section

```yaml
image:
  repository: <YOUR_ECR_URI>/cicd-demo-app
  tag: "latest"
  pullPolicy: IfNotPresent
```

- `repository` — ECR URI for your image
- `tag` — **this line is updated by the CD workflow on every deployment**
- `pullPolicy: IfNotPresent` — only pull the image if not already cached on the node

### Service section

```yaml
service:
  type: LoadBalancer
  port: 80
  targetPort: 3000
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

- `type: LoadBalancer` — tells Kubernetes to create an external load balancer
- The annotations tell the **AWS Load Balancer Controller** to create an NLB (Network Load Balancer)
- `internet-facing` — the NLB gets a public hostname
- Port 80 (public) maps to container port 3000

### Resources section

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "250m"
    memory: "256Mi"
```

- `requests` — the minimum guaranteed to the pod; used for **scheduling** decisions
  - `100m` = 100 millicores = 0.1 CPU
  - Kubernetes scheduler only places a pod on a node that has at least this much free
- `limits` — the maximum the pod can use
  - If the pod exceeds memory limit → OOMKilled (Out Of Memory)
  - If it exceeds CPU limit → throttled (slowed down, not killed)

### Autoscaling section

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

- Creates an **HPA** (HorizontalPodAutoscaler)
- Kubernetes monitors average CPU across all pods
- When average CPU > 70% → add a pod (up to maxReplicas)
- When CPU drops → remove pods (down to minReplicas)

### Security context

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

- `runAsNonRoot: true` — Kubernetes rejects the pod if it tries to run as root
- `readOnlyRootFilesystem: true` — container can't write to its filesystem (security)
  - That's why we added a writable `emptyDir` volume mounted at `/tmp`
- `capabilities: drop: [ALL]` — removes all Linux kernel capabilities from the container

---

## File: `templates/deployment.yaml`

### Template syntax

```yaml
metadata:
  name: {{ include "cicd-demo-app.fullname" . }}
```

- `{{ }}` — Helm template expression
- `include "cicd-demo-app.fullname" .` — calls the helper function defined in `_helpers.tpl`
- The `.` passes the current context (all values + chart metadata)

```yaml
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
```

- `{{- if ... }}` — conditional rendering; `{{- }}` trims whitespace before the block
- `.Values.autoscaling.enabled` — reads the `autoscaling.enabled` field from values.yaml
- If HPA is enabled, we don't set `replicas` in the Deployment (HPA manages it)

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

- `RollingUpdate` — replace pods one at a time (zero downtime)
- `maxSurge: 1` — allow 1 extra pod during the update (temporarily 3 pods if desired=2)
- `maxUnavailable: 0` — never have fewer than desired number of ready pods

```yaml
      containers:
        - image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

- Helm substitutes this with the actual values from values.yaml
- e.g. `340529310701.dkr.ecr.ap-south-1.amazonaws.com/cicd-demo-app:abc123`

```yaml
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 20
```

- Kubernetes sends GET `/health` every 20 seconds
- If it fails 3 times → pod is killed and restarted
- `initialDelaySeconds: 15` — wait 15s before first check (app needs time to start)

```yaml
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
```

- **Readiness** — is the pod ready to receive traffic?
- Until this passes, the pod is NOT added to the Service's endpoints
- Use case: app is running but still warming up a cache

```yaml
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
```

- Ensures pods are spread across different nodes
- `maxSkew: 1` — max difference of 1 pod between any two nodes
- Prevents all pods from landing on the same node (HA concern)

---

## File: `templates/hpa.yaml`

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
```

- The whole file is wrapped in `{{- if .Values.autoscaling.enabled }}` — only rendered if enabled
- `averageUtilization: 70` — scale up when average CPU across pods exceeds 70%

---

## File: `templates/pdb.yaml`

```yaml
kind: PodDisruptionBudget
spec:
  minAvailable: 1
```

- **PDB** protects against accidental mass pod termination
- During node maintenance (`kubectl drain`), Kubernetes must evict pods
- PDB says: "always keep at least 1 pod running"
- Without PDB, a node drain could take down all pods simultaneously

---

## Helm Commands

```bash
# Install a chart (first time)
helm install cicd-demo-app ./helm/cicd-demo-app -n cicd-demo --create-namespace

# Upgrade (subsequent deployments)
helm upgrade cicd-demo-app ./helm/cicd-demo-app -n cicd-demo

# Install OR upgrade (idempotent — safe to run anytime)
helm upgrade --install cicd-demo-app ./helm/cicd-demo-app -n cicd-demo --create-namespace

# Override values at deploy time
helm upgrade --install cicd-demo-app ./helm/cicd-demo-app \
  --set image.tag=abc123 \
  --set replicaCount=3

# Use a separate values file (e.g. for prod)
helm upgrade --install cicd-demo-app ./helm/cicd-demo-app \
  -f helm/cicd-demo-app/values.yaml \
  -f helm/cicd-demo-app/values-prod.yaml

# See what Kubernetes YAML Helm would generate (without deploying)
helm template cicd-demo-app ./helm/cicd-demo-app

# See release history
helm history cicd-demo-app -n cicd-demo

# Roll back to previous release
helm rollback cicd-demo-app -n cicd-demo
helm rollback cicd-demo-app 2 -n cicd-demo   # roll back to revision 2

# See current values of a deployed chart
helm get values cicd-demo-app -n cicd-demo

# Uninstall (deletes all K8s resources created by this chart)
helm uninstall cicd-demo-app -n cicd-demo

# Lint chart for errors
helm lint ./helm/cicd-demo-app

# Package chart into a .tgz
helm package ./helm/cicd-demo-app
```
