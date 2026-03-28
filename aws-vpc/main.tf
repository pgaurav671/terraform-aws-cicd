# ==============================================================================
# AWS VPC Architecture - Terraform Configuration
# ==============================================================================
#
# Architecture Overview:
#   ┌─────────────────────────────────────────────────────────────┐
#   │  VPC (10.0.0.0/16)                                          │
#   │                                                              │
#   │  ┌──────────────────┐    ┌──────────────────┐               │
#   │  │  Public Subnet 1 │    │  Public Subnet 2 │  ← IGW        │
#   │  │  10.0.1.0/24     │    │  10.0.2.0/24     │               │
#   │  │  (AZ-a)          │    │  (AZ-b)          │               │
#   │  └────────┬─────────┘    └──────────────────┘               │
#   │           │ NAT GW                                           │
#   │  ┌────────▼─────────┐    ┌──────────────────┐               │
#   │  │  Private App 1   │    │  Private App 2   │  ← App Tier   │
#   │  │  10.0.10.0/24    │    │  10.0.11.0/24    │               │
#   │  │  (AZ-a)          │    │  (AZ-b)          │               │
#   │  └────────┬─────────┘    └────────┬─────────┘               │
#   │           │                       │                          │
#   │  ┌────────▼─────────┐    ┌────────▼─────────┐               │
#   │  │  Private DB 1    │    │  Private DB 2    │  ← DB Tier    │
#   │  │  10.0.20.0/24    │    │  10.0.21.0/24    │               │
#   │  │  (AZ-a)          │    │  (AZ-b)          │               │
#   │  └──────────────────┘    └──────────────────┘               │
#   └─────────────────────────────────────────────────────────────┘
#
# Resources created:
#   - VPC with DNS support
#   - 2 Public Subnets (multi-AZ)
#   - 2 Private App Subnets (multi-AZ)
#   - 2 Private DB Subnets (multi-AZ)
#   - Internet Gateway
#   - NAT Gateway + Elastic IP
#   - Route Tables (public, private-app, private-db)
#   - Security Groups (bastion, alb, app, db)
#   - Network ACLs (public, private-app, private-db)
#   - VPC Flow Logs → CloudWatch Logs
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider — credentials are read from environment variables:
#   AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (never hardcode credentials)
provider "aws" {
  region = var.region
}

# ==============================================================================
# VPC
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = var.vpc_name
  })
}

# ==============================================================================
# Internet Gateway — allows public subnets to reach the internet
# ==============================================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# ==============================================================================
# Subnets
# ==============================================================================

# Public subnets — one per AZ, instances get public IPs automatically
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-public-subnet-${count.index + 1}"
    Tier = "Public"
  })
}

# Private app subnets — one per AZ, no direct internet access
resource "aws_subnet" "private_app" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-app-subnet-${count.index + 1}"
    Tier = "Private-App"
  })
}

# Private DB subnets — one per AZ, isolated from internet (no NAT route)
resource "aws_subnet" "private_db" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-db-subnet-${count.index + 1}"
    Tier = "Private-DB"
  })
}

# ==============================================================================
# NAT Gateway — allows private app subnets to initiate outbound connections
# Placed in the first public subnet; add a second for full HA if needed.
# Controlled by var.enable_nat_gateway (set false for free tier).
# ==============================================================================

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  depends_on = [aws_internet_gateway.igw]

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.igw]

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-nat-gw"
  })
}

# ==============================================================================
# Route Tables
# ==============================================================================

# --- Public Route Table ---
# Default route → Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private App Route Table ---
# Default route → NAT Gateway (only when enable_nat_gateway = true)
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat[0].id
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-app-rt"
  })
}

resource "aws_route_table_association" "private_app" {
  count          = length(aws_subnet.private_app)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# --- Private DB Route Table ---
# No default route — DB tier is completely isolated from the internet
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-db-rt"
  })
}

resource "aws_route_table_association" "private_db" {
  count          = length(aws_subnet.private_db)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# ==============================================================================
# Security Groups
# ==============================================================================

# --- Bastion Host ---
# Allows SSH only from trusted IP ranges defined in var.trusted_cidr_blocks
resource "aws_security_group" "bastion" {
  name        = "${var.vpc_name}-bastion-sg"
  description = "Bastion host: SSH inbound from trusted IPs only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from trusted CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-bastion-sg"
  })
}

# --- Application Load Balancer ---
# Accepts HTTP/HTTPS from the internet; forwards to app tier
resource "aws_security_group" "alb" {
  name        = "${var.vpc_name}-alb-sg"
  description = "ALB: HTTP/HTTPS inbound from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-alb-sg"
  })
}

# --- App Tier ---
# Accepts app traffic from ALB and SSH from Bastion only
resource "aws_security_group" "app" {
  name        = "${var.vpc_name}-app-sg"
  description = "App tier: app port from ALB, SSH from bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-app-sg"
  })
}

# --- Database Tier ---
# Accepts DB connections from app tier only; outbound restricted to VPC
resource "aws_security_group" "db" {
  name        = "${var.vpc_name}-db-sg"
  description = "DB tier: DB port from app tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "DB port from app tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Outbound within VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-db-sg"
  })
}

# ==============================================================================
# Network ACLs — subnet-level stateless firewall (second layer of defence)
# ==============================================================================

# --- Public Subnets NACL ---
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Inbound: HTTP
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  # Inbound: HTTPS
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  # Inbound: SSH
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }
  # Inbound: Ephemeral ports (return traffic for outbound connections)
  ingress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  # Outbound: Allow all
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-public-nacl"
  })
}

# --- Private App Subnets NACL ---
resource "aws_network_acl" "private_app" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private_app[*].id

  # Inbound: App port from VPC
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.app_port
    to_port    = var.app_port
  }
  # Inbound: SSH from VPC (bastion)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }
  # Inbound: Ephemeral return traffic
  ingress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  # Outbound: Allow all
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-app-nacl"
  })
}

# --- Private DB Subnets NACL ---
resource "aws_network_acl" "private_db" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private_db[*].id

  # Inbound: DB port from each private app subnet
  dynamic "ingress" {
    for_each = var.private_app_subnet_cidrs
    content {
      rule_no    = 100 + ingress.key * 10
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = var.db_port
      to_port    = var.db_port
    }
  }
  # Inbound: Ephemeral return traffic within VPC
  ingress {
    rule_no    = 140
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }
  # Outbound: VPC only (DB tier never initiates internet traffic)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-private-db-nacl"
  })
}

# ==============================================================================
# VPC Flow Logs → CloudWatch Logs
# Captures all accepted/rejected traffic for security auditing and debugging
# Controlled by var.enable_flow_logs (set false for free tier).
# ==============================================================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/flow-logs/${var.vpc_name}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-flow-logs"
  })
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.vpc_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.vpc_name}-flow-logs-policy"
  role  = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  count           = var.enable_flow_logs ? 1 : 0
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-flow-log"
  })
}
