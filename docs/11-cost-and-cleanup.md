# 11 — Cost & Cleanup

## AWS Cost Breakdown (ap-south-1 / Mumbai)

### What runs 24/7 while the cluster is up

| Resource | Price | Per Day | Per Month |
|---|---|---|---|
| EKS Control Plane | $0.10/hr | $2.40 | $72.00 |
| t3.small (1 node) | $0.027/hr | $0.65 | $19.44 |
| NAT Gateway | $0.045/hr | $1.08 | $32.40 |
| NAT Gateway data | $0.045/GB | varies | varies |
| NLB (app load balancer) | $0.008/hr | $0.19 | $5.76 |
| NLB (argocd load balancer) | $0.008/hr | $0.19 | $5.76 |
| ECR storage | $0.10/GB/month | ~$0 | ~$0 |
| **Total (approx)** | **~$0.19/hr** | **~$4.50** | **~$135** |

### Your $120 credits

- At ~$4.50/day you get roughly **26 days** of uptime
- Credits apply to most AWS services except some support plans
- Check usage: AWS Console → Billing → Credits

---

## What is NOT free tier

EKS itself is **never free tier**. The $0.10/hr control plane charge starts immediately.

Free tier eligible things in this project:
- ECR: first 500MB storage free per month
- Data transfer in: always free

Everything else (EKS, EC2, NAT GW, NLB) costs real money.

---

## How to minimize costs during development

### 1. Destroy when not in use (most effective)
```bash
cd cicd-k8s-project/terraform/eks
terraform destroy
```
Brings cost to $0 instantly. Takes ~15 min to recreate.

### 2. Scale down to 0 nodes at end of day
Stops EC2 charges but EKS control plane still charges $0.10/hr:
```bash
# Scale node group to 0 (stops EC2 charges)
aws eks update-nodegroup-config \
  --cluster-name cicd-demo-cluster \
  --nodegroup-name cicd-demo-cluster-nodes-xxx \
  --scaling-config minSize=0,maxSize=2,desiredSize=0 \
  --region ap-south-1

# Scale back up
aws eks update-nodegroup-config \
  --cluster-name cicd-demo-cluster \
  --nodegroup-name cicd-demo-cluster-nodes-xxx \
  --scaling-config minSize=1,maxSize=2,desiredSize=1 \
  --region ap-south-1
```

### 3. Delete the NLBs when not testing traffic
The two NLBs (app + ArgoCD) cost ~$0.38/day combined:
```bash
# Delete ArgoCD's NLB by switching back to ClusterIP
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "ClusterIP"}}'
```
Use `kubectl port-forward` to access ArgoCD locally instead.

---

## Cleanup Order

When done with the project, destroy in this order to avoid dependency errors:

### Step 1: Delete Kubernetes resources first
```bash
# Delete the ArgoCD application (removes app K8s resources)
kubectl delete -f cicd-k8s-project/argocd/argocd-app.yaml

# Delete ArgoCD itself
kubectl delete -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Delete the app namespace
kubectl delete namespace cicd-demo
```

### Step 2: Terraform destroy
```bash
cd cicd-k8s-project/terraform/eks
terraform destroy
```

Type `yes` when prompted. This deletes:
- EKS cluster + node group
- VPC + all subnets, IGW, NAT GW, route tables
- ECR repository + all images
- All IAM roles
- Security groups

Takes ~10-15 minutes.

### Step 3: Verify in AWS Console
Go to these services and confirm they're empty:
- EKS → Clusters
- EC2 → Instances
- EC2 → Load Balancers
- EC2 → NAT Gateways
- VPC → Your VPCs
- ECR → Repositories

### Step 4: Check for orphaned resources
Some resources aren't managed by Terraform (created by K8s controllers):
```bash
# Load balancers created by the AWS LB Controller
aws elbv2 describe-load-balancers --region ap-south-1

# Security groups created by EKS
aws ec2 describe-security-groups --region ap-south-1 \
  --filters "Name=tag:kubernetes.io/cluster/cicd-demo-cluster,Values=owned"
```

If any exist, delete them manually in the console or with AWS CLI.

---

## Billing alerts (set these up now)

```
AWS Console → Billing → Budgets → Create budget
```

Recommended: Set an alert at $50 so you get an email before credits run out.

Also enable:
```
AWS Console → Billing → Billing preferences → Receive PDF invoice by email
```

---

## Check current spend

```bash
# Current month cost breakdown by service
aws ce get-cost-and-usage \
  --time-period Start=2026-03-01,End=2026-03-31 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region us-east-1 \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
```

(Cost Explorer API is always queried from `us-east-1` regardless of your region)

---

## Quick cost check URLs

After logging into AWS Console:
- **Current charges**: Billing → Bills
- **Credits remaining**: Billing → Credits
- **Cost by service**: Billing → Cost Explorer
- **Free tier usage**: Billing → Free Tier
