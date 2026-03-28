# terraform-aws-cicd

AWS Infrastructure as Code with Terraform, CI/CD pipelines, Kubernetes (EKS), Helm, and ArgoCD.

## Repository Structure

```
terraform-aws-cicd/
├── aws-ec2/          # EC2 instances with security groups
├── aws-s3/           # S3 buckets with versioning & policies
├── aws-vpc/          # Production-ready VPC architecture
└── cicd-k8s-project/ # Full CI/CD pipeline + EKS + ArgoCD
```

---

## Architecture Overview

```mermaid
graph TD
    subgraph Developer
        DEV[👨‍💻 Developer]
    end

    subgraph GitHub
        REPO[GitHub Repository]
        CI[CI Workflow\nBuild · Test · Push]
        CD[CD Workflow\nUpdate Helm Values]
    end

    subgraph AWS["AWS (ap-south-1)"]
        ECR[Amazon ECR\nContainer Registry]

        subgraph VPC["VPC 10.0.0.0/16"]
            subgraph Public["Public Subnets"]
                NAT[NAT Gateway]
                NLB[Network Load Balancer]
            end

            subgraph Private["Private Subnets"]
                subgraph EKS[EKS Cluster]
                    NG[Node Group\nt3.small × 1-2]
                    subgraph NS[Namespace: cicd-demo]
                        POD1[App Pod 1]
                        POD2[App Pod 2]
                    end
                    subgraph ARGOCD[Namespace: argocd]
                        ARGO[ArgoCD Server]
                    end
                end
            end
        end
    end

    DEV -->|git push| REPO
    REPO -->|triggers| CI
    CI -->|docker push| ECR
    CI -->|triggers| CD
    CD -->|updates values.yaml| REPO
    ARGO -->|watches Git\nauto-sync| REPO
    ARGO -->|deploys Helm chart| NS
    ECR -->|pulls image| NG
    NLB -->|routes traffic| POD1
    NLB -->|routes traffic| POD2
```

---

## CI/CD Pipeline Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant CI as CI Workflow
    participant ECR as Amazon ECR
    participant CD as CD Workflow
    participant ARGO as ArgoCD
    participant K8S as EKS Cluster

    Dev->>GH: git push to main
    GH->>CI: trigger CI workflow

    rect rgb(230, 245, 255)
        Note over CI: CI Phase
        CI->>CI: npm install & run tests
        CI->>CI: docker build (multi-stage)
        CI->>CI: trivy security scan
        CI->>ECR: docker push :sha + :latest
    end

    CI->>CD: trigger CD workflow (on success)

    rect rgb(230, 255, 230)
        Note over CD: CD Phase
        CD->>GH: update helm/values.yaml\n(new image tag)
        CD->>GH: commit [skip ci]
    end

    GH->>ARGO: webhook / poll detects change
    ARGO->>GH: pull updated Helm chart
    ARGO->>K8S: helm upgrade (rolling update)
    K8S->>ECR: pull new image
    K8S-->>ARGO: deployment healthy ✓
    ARGO-->>Dev: sync status: Synced + Healthy
```

---

## EKS Infrastructure

```mermaid
graph LR
    subgraph Terraform["Terraform Modules"]
        TF_VPC[terraform-aws-modules/vpc]
        TF_EKS[terraform-aws-modules/eks]
        TF_IAM[terraform-aws-modules/iam\nIRSA for LB Controller]
    end

    subgraph AWS_Resources["AWS Resources Created"]
        VPC[VPC + Subnets\nIGW + NAT GW]
        ECR_R[ECR Repository\nLifecycle: keep 10 images]
        EKS_C[EKS Cluster v1.29]
        NG_R[Node Group\nt3.small ON_DEMAND]
        ADDONS[Add-ons\nCoreDNS · kube-proxy\nvpc-cni · ebs-csi]
        LB_ROLE[IAM Role\nALB Controller IRSA]
    end

    TF_VPC --> VPC
    TF_EKS --> EKS_C
    TF_EKS --> NG_R
    TF_EKS --> ADDONS
    TF_IAM --> LB_ROLE
    VPC --> EKS_C
    EKS_C --> ECR_R
```

---

## Helm Chart Structure

```mermaid
graph TD
    CHART[cicd-demo-app\nHelm Chart v0.1.0]

    CHART --> DEPLOY[Deployment\n2 replicas · RollingUpdate]
    CHART --> SVC[Service\nNLB · internet-facing]
    CHART --> HPA[HPA\nmin:2 max:5 · CPU 70%]
    CHART --> PDB[PodDisruptionBudget\nminAvailable: 1]
    CHART --> SA[ServiceAccount]
    CHART --> CM[ConfigMap]
    CHART --> NS[Namespace: cicd-demo]

    DEPLOY --> PROBE1[Liveness /health]
    DEPLOY --> PROBE2[Readiness /health]
    DEPLOY --> SEC[SecurityContext\nnon-root · readOnly FS]
```

---

## Projects

### [aws-vpc](./aws-vpc/)
Production-ready VPC with public/private subnets, NAT Gateway, Internet Gateway, and security groups across multiple AZs.

### [aws-ec2](./aws-ec2/)
EC2 instance provisioning with key pairs, security groups, and user data scripts.

### [aws-s3](./aws-s3/)
S3 bucket setup with versioning, lifecycle policies, and bucket policies.

### [cicd-k8s-project](./cicd-k8s-project/)
Full end-to-end CI/CD pipeline:
- **App** — Node.js Express REST API with Jest tests
- **Docker** — Multi-stage Dockerfile with health checks
- **CI** — GitHub Actions: test → build → push to ECR → Trivy scan
- **CD** — GitHub Actions: update Helm values → ArgoCD auto-sync
- **Terraform** — EKS cluster + VPC + ECR + LB Controller IRSA
- **Helm** — Deployment, Service (NLB), HPA, PDB, ConfigMap
- **ArgoCD** — GitOps auto-sync with self-heal and prune

---

## Quick Start

### 1. Provision Infrastructure
```bash
cd cicd-k8s-project/terraform/eks
terraform init
terraform apply
```

### 2. Install ArgoCD
```bash
bash cicd-k8s-project/argocd/install-argocd.sh cicd-demo-cluster ap-south-1
```

### 3. Install AWS Load Balancer Controller
```bash
bash cicd-k8s-project/argocd/install-lb-controller.sh \
  cicd-demo-cluster ap-south-1 <lb_controller_role_arn>
```

### 4. Apply ArgoCD Application
```bash
# Update repoURL in argocd/argocd-app.yaml first
kubectl apply -f cicd-k8s-project/argocd/argocd-app.yaml
```

### 5. Trigger CI/CD
```bash
git push origin main   # → CI builds & pushes → CD deploys via ArgoCD
```

### 6. Test Traffic
```bash
bash cicd-k8s-project/scripts/test-traffic.sh
```

---

## GitHub Actions Secrets Required

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `ARGOCD_ADMIN_PASSWORD` | ArgoCD admin password (set after install) |

## Cost Estimate (ap-south-1)

| Resource | Cost/hr |
|---|---|
| EKS Control Plane | $0.10 |
| t3.small node × 1 | $0.027 |
| NAT Gateway | $0.045 |
| NLB | $0.008 |
| **Total** | **~$0.18/hr** |

> Destroy when not in use: `cd cicd-k8s-project/terraform/eks && terraform destroy`
