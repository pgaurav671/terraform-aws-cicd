# 10 — kubectl Cheatsheet

## Setup

```bash
# Configure kubectl for EKS (run once after terraform apply)
aws eks update-kubeconfig --name cicd-demo-cluster --region ap-south-1

# Verify connection
kubectl cluster-info
kubectl get nodes
```

---

## Nodes

```bash
kubectl get nodes                    # list nodes
kubectl get nodes -o wide            # with IP, OS, version
kubectl describe node <node-name>    # full details, events, conditions
kubectl top nodes                    # CPU and memory usage (needs metrics-server)
```

---

## Namespaces

```bash
kubectl get namespaces               # list all namespaces
kubectl create namespace cicd-demo
kubectl delete namespace cicd-demo   # WARNING: deletes everything inside

# Run commands in a specific namespace
kubectl get pods -n cicd-demo
kubectl get pods -n argocd

# Set default namespace for current context (so you don't type -n every time)
kubectl config set-context --current --namespace=cicd-demo
```

---

## Pods

```bash
kubectl get pods -n cicd-demo                    # list pods
kubectl get pods -n cicd-demo -o wide            # with node and IP
kubectl get pods -n cicd-demo -w                 # watch (live updates)

kubectl describe pod <pod-name> -n cicd-demo     # full details + events
# Events section shows why a pod is crashing/pending

kubectl logs <pod-name> -n cicd-demo             # logs
kubectl logs <pod-name> -n cicd-demo -f          # follow (like tail -f)
kubectl logs <pod-name> -n cicd-demo --previous  # logs from crashed previous container

# Get a shell inside a running pod
kubectl exec -it <pod-name> -n cicd-demo -- sh
kubectl exec -it <pod-name> -n cicd-demo -- /bin/bash

# Copy files to/from pod
kubectl cp localfile.txt cicd-demo/<pod-name>:/tmp/
kubectl cp cicd-demo/<pod-name>:/tmp/file.txt ./local/

# Delete a pod (Deployment will recreate it)
kubectl delete pod <pod-name> -n cicd-demo

# Force delete stuck pod
kubectl delete pod <pod-name> -n cicd-demo --grace-period=0 --force
```

---

## Deployments

```bash
kubectl get deployments -n cicd-demo
kubectl describe deployment cicd-demo-app -n cicd-demo

# Watch rollout progress
kubectl rollout status deployment/cicd-demo-app -n cicd-demo

# Rollout history
kubectl rollout history deployment/cicd-demo-app -n cicd-demo

# Roll back to previous version
kubectl rollout undo deployment/cicd-demo-app -n cicd-demo

# Roll back to specific revision
kubectl rollout undo deployment/cicd-demo-app -n cicd-demo --to-revision=2

# Manually scale replicas
kubectl scale deployment cicd-demo-app -n cicd-demo --replicas=3

# Update image manually (use helm/argocd instead in production)
kubectl set image deployment/cicd-demo-app \
  cicd-demo-app=<ECR_URI>/cicd-demo-app:new-tag -n cicd-demo

# Restart all pods (rolling restart, no downtime)
kubectl rollout restart deployment/cicd-demo-app -n cicd-demo
```

---

## Services

```bash
kubectl get services -n cicd-demo
kubectl get svc -n cicd-demo                            # svc is shorthand

# Get the Load Balancer URL
kubectl get svc cicd-demo-app -n cicd-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

kubectl describe svc cicd-demo-app -n cicd-demo
```

---

## ConfigMaps and Secrets

```bash
kubectl get configmaps -n cicd-demo
kubectl describe configmap cicd-demo-app-config -n cicd-demo

kubectl get secrets -n argocd
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## HPA (Horizontal Pod Autoscaler)

```bash
kubectl get hpa -n cicd-demo
kubectl describe hpa cicd-demo-app -n cicd-demo

# Watch HPA scaling in real time
kubectl get hpa -n cicd-demo -w
```

---

## Events (for debugging)

```bash
# See recent events in a namespace
kubectl get events -n cicd-demo --sort-by='.lastTimestamp'

# See events for a specific pod
kubectl describe pod <pod-name> -n cicd-demo | grep -A 20 Events:
```

Common events to look for:
- `BackOff` — container is crash-looping
- `Pulling` / `Pulled` — image pull status
- `FailedScheduling` — not enough resources on nodes
- `OOMKilled` — pod exceeded memory limit

---

## Resource usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n cicd-demo
kubectl top pods -n cicd-demo --sort-by=cpu
kubectl top pods -n cicd-demo --sort-by=memory
```

---

## Useful output formats

```bash
# YAML output (see the full spec)
kubectl get deployment cicd-demo-app -n cicd-demo -o yaml

# JSON output
kubectl get pod <pod-name> -n cicd-demo -o json

# Extract specific field with jsonpath
kubectl get pod <pod-name> -n cicd-demo \
  -o jsonpath='{.status.podIP}'

# All resources in a namespace
kubectl get all -n cicd-demo
```

---

## Port forwarding (for local testing)

```bash
# Forward local port 8080 to pod port 3000
kubectl port-forward pod/<pod-name> 8080:3000 -n cicd-demo

# Forward to a service (round-robins to pods)
kubectl port-forward svc/cicd-demo-app 8080:80 -n cicd-demo

# Forward ArgoCD to localhost
kubectl port-forward svc/argocd-server 8080:443 -n argocd
```

Then access: `http://localhost:8080`

---

## Contexts (multiple clusters)

```bash
# List all clusters/contexts you have configured
kubectl config get-contexts

# Switch to a different cluster
kubectl config use-context <context-name>

# See current context
kubectl config current-context

# Rename a context
kubectl config rename-context old-name new-name
```

---

## Quick Debugging Checklist

When a pod is not working:

```bash
# 1. What's the pod status?
kubectl get pods -n cicd-demo

# 2. Why is it in that status?
kubectl describe pod <pod-name> -n cicd-demo
# Look at: Events section, Conditions, Container status

# 3. What are the logs saying?
kubectl logs <pod-name> -n cicd-demo
kubectl logs <pod-name> -n cicd-demo --previous  # if it already crashed

# 4. Can the pod reach the network? (run a debug shell)
kubectl exec -it <pod-name> -n cicd-demo -- sh
# Inside: wget -qO- http://localhost:3000/health

# 5. Are there resource issues?
kubectl top pods -n cicd-demo
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```
