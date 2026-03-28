# Project Documentation Index

Complete guide for the `terraform-aws-cicd` project — from a simple Node.js app to a full
GitOps CI/CD pipeline on AWS EKS.

## Documents

| # | File | What it covers |
|---|------|----------------|
| 1 | [01-nodejs-app.md](./01-nodejs-app.md) | Node.js Express app, REST endpoints, tests |
| 2 | [02-docker.md](./02-docker.md) | Dockerfile, multi-stage builds, docker-compose |
| 3 | [03-github-actions-ci.md](./03-github-actions-ci.md) | CI workflow — test, build, push to ECR, Trivy scan |
| 4 | [04-github-actions-cd.md](./04-github-actions-cd.md) | CD workflow — Helm update, ArgoCD sync |
| 5 | [05-terraform-eks.md](./05-terraform-eks.md) | Terraform — VPC, EKS, ECR, IRSA, all commands |
| 6 | [06-helm.md](./06-helm.md) | Helm chart — Deployment, Service, HPA, PDB |
| 7 | [07-argocd-gitops.md](./07-argocd-gitops.md) | ArgoCD — install, GitOps concepts, commands |
| 8 | [08-git-github.md](./08-git-github.md) | Git setup, remote, .gitignore, gh CLI |
| 9 | [09-end-to-end-flow.md](./09-end-to-end-flow.md) | Full pipeline walkthrough — push to deploy |
| 10 | [10-kubectl-cheatsheet.md](./10-kubectl-cheatsheet.md) | kubectl commands for day-to-day cluster work |
| 11 | [11-cost-and-cleanup.md](./11-cost-and-cleanup.md) | AWS costs, how to destroy, free tier notes |

## Quick Reference

```
git push → CI (test+build+push ECR) → CD (update Helm) → ArgoCD (deploy to EKS) → NLB → Traffic
```

## Project Layout

```
terraform-aws-cicd/
├── docs/                          ← you are here
├── aws-ec2/                       ← EC2 Terraform
├── aws-s3/                        ← S3 Terraform
├── aws-vpc/                       ← VPC Terraform
└── cicd-k8s-project/
    ├── app/                       ← Node.js app + tests
    ├── .github/workflows/         ← CI and CD pipelines
    ├── terraform/eks/             ← EKS infrastructure
    ├── helm/cicd-demo-app/        ← Helm chart
    ├── argocd/                    ← ArgoCD manifests + install scripts
    └── scripts/                   ← Traffic test script
```
