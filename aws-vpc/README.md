# AWS VPC Architecture — Terraform

A production-ready, multi-tier VPC on AWS built with Terraform.

---

## Architecture Diagram

```mermaid
graph TD
    Internet(["🌐 Internet"])

    subgraph AWS["AWS — ap-south-1"]
        IGW["🔀 Internet Gateway\nprod-vpc-igw"]

        subgraph VPC["VPC — 10.0.0.0/16  (prod-vpc)"]

            subgraph PUB["Public Tier"]
                PUB1["📦 Public Subnet 1\n10.0.1.0/24\nap-south-1a\n─────────────\nBastion Host\nALB"]
                PUB2["📦 Public Subnet 2\n10.0.2.0/24\nap-south-1b\n─────────────\nALB"]
            end

            NAT["🔁 NAT Gateway\n+ Elastic IP\n(optional)"]

            subgraph APP["Private App Tier"]
                APP1["📦 Private App Subnet 1\n10.0.10.0/24\nap-south-1a\n─────────────\nApp Servers"]
                APP2["📦 Private App Subnet 2\n10.0.11.0/24\nap-south-1b\n─────────────\nApp Servers"]
            end

            subgraph DB["Private DB Tier — Fully Isolated"]
                DB1["📦 Private DB Subnet 1\n10.0.20.0/24\nap-south-1a\n─────────────\nRDS / ElastiCache"]
                DB2["📦 Private DB Subnet 2\n10.0.21.0/24\nap-south-1b\n─────────────\nRDS / ElastiCache"]
            end

            CW["📋 CloudWatch\nVPC Flow Logs\n(optional)"]
        end
    end

    Internet -->|HTTP · HTTPS · SSH| IGW
    IGW --> PUB1
    IGW --> PUB2
    PUB1 -->|outbound only| NAT
    NAT --> APP1
    NAT --> APP2
    APP1 --> DB1
    APP2 --> DB2
    VPC -.->|all traffic logs| CW
```

---

## Resources Created

| Resource | Count | Purpose |
|---|---|---|
| VPC | 1 | Isolated network with DNS enabled |
| Internet Gateway | 1 | Public internet access |
| Public Subnets | 2 (multi-AZ) | ALB, Bastion host |
| Private App Subnets | 2 (multi-AZ) | Application servers |
| Private DB Subnets | 2 (multi-AZ) | Databases (RDS, ElastiCache) |
| Elastic IP | 1 | Static IP for NAT Gateway |
| NAT Gateway | 1 | Outbound internet for private subnets |
| Route Tables | 3 | Public, Private-App, Private-DB |
| Security Group: Bastion | 1 | SSH from trusted IPs only |
| Security Group: ALB | 1 | HTTP/HTTPS from internet |
| Security Group: App | 1 | App port from ALB + SSH from Bastion |
| Security Group: DB | 1 | DB port from app tier only |
| Network ACL: Public | 1 | Subnet-level traffic filtering |
| Network ACL: Private App | 1 | Subnet-level traffic filtering |
| Network ACL: Private DB | 1 | Subnet-level traffic filtering |
| VPC Flow Logs | 1 | All traffic captured to CloudWatch |
| IAM Role + Policy | 1 each | Flow logs write permission |

---

## Traffic Flow

```mermaid
sequenceDiagram
    actor User as 👤 User / Client
    participant IGW  as Internet Gateway
    participant ALB  as ALB (Public Subnet)
    participant APP  as App Server (Private)
    participant DB   as Database (Private)
    participant NAT  as NAT Gateway

    Note over User,DB: Inbound — HTTPS request lifecycle
    User  ->>  IGW : HTTPS :443
    IGW   ->>  ALB : forward (alb-sg allows 80/443)
    ALB   ->>  APP : forward (app-sg allows app_port from alb-sg)
    APP   ->>  DB  : query   (db-sg allows db_port from app-sg)
    DB    -->> APP : result
    APP   -->> ALB : response
    ALB   -->> User: response

    Note over User,DB: SSH — Bastion access path
    User  ->>  IGW : SSH :22
    IGW   ->>  ALB : → Bastion (bastion-sg allows :22 from trusted IPs)
    ALB   ->>  APP : SSH :22 (app-sg allows :22 from bastion-sg)

    Note over APP,NAT: Outbound — Private app → internet (e.g. package install)
    APP   ->>  NAT : outbound request
    NAT   ->>  IGW : via Elastic IP
    IGW   -->> NAT : response
    NAT   -->> APP : return traffic

    Note over DB: DB tier has NO outbound internet route
```

---

## Security Model

### Security Groups (stateful)

```mermaid
graph LR
    INET(["🌐 Internet\n0.0.0.0/0"])
    TRUST(["🔒 Trusted IP\nyour-ip/32"])

    subgraph SGs["Security Groups — least-privilege chain"]
        BASTION["bastion-sg\n─────────────\nIN  :22 ← trusted IPs\nOUT all"]
        ALB["alb-sg\n─────────────\nIN  :80  ← internet\nIN  :443 ← internet\nOUT all"]
        APP["app-sg\n─────────────\nIN  :app_port ← alb-sg\nIN  :22       ← bastion-sg\nOUT all"]
        DB["db-sg\n─────────────\nIN  :db_port ← app-sg\nOUT VPC CIDR only"]
    end

    TRUST -->|SSH :22| BASTION
    INET  -->|:80 / :443| ALB
    ALB   -->|app_port| APP
    BASTION -->|SSH :22| APP
    APP   -->|db_port| DB
```

### Network ACLs (stateless — second layer)

```mermaid
graph TD
    subgraph NACL_PUB["NACL — Public Subnets"]
        direction LR
        P_IN["INBOUND\n100 TCP :80   ALLOW\n110 TCP :443  ALLOW\n120 TCP :22   ALLOW\n140 TCP :1024-65535 ALLOW"]
        P_OUT["OUTBOUND\n100 ALL  ALLOW"]
    end

    subgraph NACL_APP["NACL — Private App Subnets"]
        direction LR
        A_IN["INBOUND\n100 TCP :app_port from VPC ALLOW\n110 TCP :22        from VPC ALLOW\n140 TCP :1024-65535       ALLOW"]
        A_OUT["OUTBOUND\n100 ALL  ALLOW"]
    end

    subgraph NACL_DB["NACL — Private DB Subnets"]
        direction LR
        D_IN["INBOUND\n100 TCP :db_port from app-subnet-1 ALLOW\n110 TCP :db_port from app-subnet-2 ALLOW\n140 TCP :1024-65535 from VPC      ALLOW"]
        D_OUT["OUTBOUND\n100 ALL to VPC CIDR ALLOW"]
    end
```

| NACL | Key Rules |
|---|---|
| Public | Allow 80/443/22 inbound; ephemeral ports; all outbound |
| Private App | Allow `app_port`/22 from VPC; ephemeral ports; all outbound |
| Private DB | Allow `db_port` from app subnets only; VPC-only outbound |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3
- AWS credentials set as environment variables:
  ```bash
  export AWS_ACCESS_KEY_ID="your-access-key"
  export AWS_SECRET_ACCESS_KEY="your-secret-key"
  ```

---

## Usage

```bash
# 1. Navigate to the module
cd aws-vpc

# 2. Initialise providers
terraform init

# 3. Preview changes
terraform plan

# 4. Apply
terraform apply

# 5. Destroy when done
terraform destroy
```

---

## Key Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `ap-south-1` | AWS region |
| `vpc_cidr` | `10.0.0.0/16` | VPC address space |
| `availability_zones` | `[ap-south-1a, ap-south-1b]` | AZs for subnets |
| `trusted_cidr_blocks` | `0.0.0.0/0` | **Restrict to your IP in production** |
| `app_port` | `8080` | Application listening port |
| `db_port` | `5432` | Database listening port |
| `flow_log_retention_days` | `30` | CloudWatch log retention |

---

## Outputs

After `terraform apply`, the following values are exported for use in other modules:

- `vpc_id` — attach EC2, RDS, ECS clusters
- `public_subnet_ids` — place ALB and bastion
- `private_app_subnet_ids` — place app servers / ECS tasks
- `private_db_subnet_ids` — place RDS subnet group
- `alb_sg_id`, `app_sg_id`, `db_sg_id` — reference from EC2/RDS modules
- `nat_gateway_public_ip` — whitelist in external services

---

## Cost Notes

- **NAT Gateway** — ~$32/month + data transfer charges. For dev/test, consider a NAT instance instead.
- **VPC Flow Logs** — CloudWatch ingestion + storage charges apply. Adjust `flow_log_retention_days` to control cost.
- All other VPC resources (subnets, route tables, IGW, NACLs, SGs) are **free**.
