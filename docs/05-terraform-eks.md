# 05 — Terraform EKS

## What Terraform Does

Terraform is **Infrastructure as Code** — you describe what AWS resources you want in
`.tf` files, and Terraform creates/updates/destroys them to match.

Instead of clicking in the AWS console, you write code. The infrastructure becomes
reproducible, version-controlled, and reviewable like any other code.

---

## How Terraform Works

```
terraform init    → download providers (AWS SDK for Terraform)
terraform plan    → compare desired state (your .tf files) vs actual state (AWS)
                    → show what will be created/changed/destroyed
terraform apply   → make the changes on AWS
terraform destroy → delete everything Terraform created
```

Terraform keeps track of what it created in a **state file** (`terraform.tfstate`).
Never delete this file, never commit it to Git (it can contain secrets).

---

## File: `terraform/eks/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "cicd-demo-cluster"
}
```

- Variables make the configuration reusable — change the default or pass `-var` flags
- `type = string` — Terraform validates that you pass a string, not a number
- Override at apply time: `terraform apply -var="aws_region=us-east-1"`
- Or use a `.tfvars` file: `terraform apply -var-file="prod.tfvars"`

---

## File: `terraform/eks/main.tf`

### Provider block

```hcl
provider "aws" {
  region = var.aws_region
}
```

- Tells Terraform to use the AWS provider and which region
- Credentials come from environment variables (`AWS_ACCESS_KEY_ID`, etc.) or `~/.aws/credentials`

### Data sources

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

- `data` = read-only — fetches info FROM AWS, doesn't create anything
- Gets the list of available AZs in your region
- Used later: `slice(data.aws_availability_zones.available.names, 0, 2)` = first 2 AZs

---

### VPC Module

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
}
```

- `module` — uses a pre-built reusable package from the Terraform Registry
- This one module creates: VPC, 4 subnets, Internet Gateway, NAT Gateway, route tables, associations
- `"${var.cluster_name}-vpc"` — string interpolation, same as template literals in JS
- `single_nat_gateway = true` — one NAT GW shared across AZs instead of one per AZ
  - Saves ~$30/month but means if that AZ goes down, private subnets lose internet

**CIDR ranges:**
- `10.0.0.0/16` = VPC range (65,536 IPs)
- `10.0.1.0/24` = private subnet AZ1 (256 IPs)
- `10.0.101.0/24` = public subnet AZ1 (256 IPs)

**The subnet tags are critical for EKS:**
```hcl
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
```
The AWS Load Balancer Controller looks for these tags to know which subnets
to place load balancers in. Without them, LB creation fails.

---

### ECR Repository

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "cicd-demo-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
```

- Creates a private container registry in your AWS account
- `MUTABLE` — you can overwrite the `:latest` tag (simpler for dev)
- `scan_on_push = true` — AWS automatically scans images for vulnerabilities on push

```hcl
resource "aws_ecr_lifecycle_policy" "app" {
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

- Automatically deletes old images when you have more than 10
- Without this, ECR fills up over time and you pay for storage

---

### EKS Module

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true
```

- `cluster_version = "1.29"` — Kubernetes version
- `subnet_ids = module.vpc.private_subnets` — worker nodes go in private subnets
  - Nodes are not directly reachable from internet — only through the load balancer
- `cluster_endpoint_public_access = true` — you can run `kubectl` from your laptop
  - In production you'd set this to false and use a VPN/bastion

```hcl
  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }
```

EKS add-ons are AWS-managed Kubernetes components:
- `coredns` — DNS for the cluster; pods use this to resolve `service-name.namespace.svc.cluster.local`
- `kube-proxy` — handles network routing between pods and services on each node
- `vpc-cni` — gives each pod a real VPC IP address (AWS-specific networking plugin)
- `aws-ebs-csi-driver` — lets Kubernetes create/mount EBS volumes as PersistentVolumes

```hcl
  eks_managed_node_groups = {
    main = {
      instance_types           = ["t3.small"]
      min_size                 = 1
      max_size                 = 2
      desired_size             = 1
      capacity_type            = "ON_DEMAND"
      iam_role_name            = "cicd-demo-ng-role"
      iam_role_use_name_prefix = false
    }
  }
```

- **Managed node group** — AWS manages the EC2 instances
  - Auto-replaces failed nodes
  - Handles node OS updates
- `t3.small` = 2 vCPU, 2GB RAM — minimum practical size for EKS nodes
- `ON_DEMAND` — standard on-demand pricing (SPOT was blocked by free-tier restriction)
- `iam_role_use_name_prefix = false` — use exact role name, not a generated prefix
  - We needed this because the auto-generated name was too long (>38 chars)

---

### IRSA — IAM Roles for Service Accounts

```hcl
module "lb_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
```

**Problem it solves:** The AWS Load Balancer Controller (running inside Kubernetes) needs
to call AWS APIs to create/manage load balancers. But you can't put IAM credentials in a pod.

**IRSA solution:**
1. EKS has an **OIDC provider** — a trust bridge between Kubernetes and AWS IAM
2. A Kubernetes **ServiceAccount** (`kube-system:aws-load-balancer-controller`) is linked to an IAM role
3. When the pod runs with that ServiceAccount, AWS automatically provides temporary credentials
4. No secrets stored anywhere

---

## File: `terraform/eks/outputs.tf`

```hcl
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
```

- Outputs print useful values after `terraform apply` completes
- `terraform output ecr_repository_url` — print a specific output
- `terraform output -json` — print all outputs as JSON (useful in scripts)

---

## All Terraform Commands

```bash
# Initialize — must run first, and after adding new modules/providers
terraform init

# Preview changes without applying
terraform plan

# Save plan to file (guarantees apply runs exactly what was planned)
terraform plan -out=tfplan
terraform apply tfplan

# Apply (creates/updates resources)
terraform apply

# Apply without confirmation prompt (for automation)
terraform apply -auto-approve

# Destroy all resources
terraform destroy

# Destroy without confirmation (careful!)
terraform destroy -auto-approve

# Show current state
terraform show

# List all resources in state
terraform state list

# Show a specific resource in state
terraform state show module.vpc.aws_vpc.this[0]

# Remove a resource from state (without destroying it on AWS)
terraform state rm aws_ecr_repository.app

# Import existing AWS resource into Terraform state
terraform import aws_ecr_repository.app cicd-demo-app

# See all outputs
terraform output

# Format all .tf files
terraform fmt

# Validate syntax
terraform validate

# See provider versions
terraform version
```

---

## What Gets Created (65 resources)

| Category | Resources |
|---|---|
| VPC | VPC, 2 public subnets, 2 private subnets, IGW, NAT GW, 2 route tables, route associations |
| ECR | Repository, lifecycle policy |
| EKS | Cluster, OIDC provider, cluster SG, node SG, node group, 4 add-ons |
| IAM | Cluster role, node role, LB controller role, 6 policy attachments |
| KMS | Encryption key for cluster secrets |

---

## Cost Breakdown (ap-south-1)

| Resource | Price |
|---|---|
| EKS Control Plane | $0.10/hr |
| t3.small ON_DEMAND (1 node) | $0.027/hr |
| NAT Gateway | $0.045/hr + $0.045/GB data |
| ECR storage | $0.10/GB/month |
| **Total running** | **~$0.17/hr (~$4/day)** |

```bash
# When done experimenting — delete everything to stop charges
cd cicd-k8s-project/terraform/eks
terraform destroy
```
