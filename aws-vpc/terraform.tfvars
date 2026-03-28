# ==============================================================================
# terraform.tfvars — override default variable values here
# Do NOT commit sensitive values (keys, passwords) to version control.
# ==============================================================================

region   = "ap-south-1"
vpc_name = "prod-vpc"
vpc_cidr = "10.0.0.0/16"

availability_zones = ["ap-south-1a", "ap-south-1b"]

public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

# IMPORTANT: Replace with your actual public IP — e.g. ["203.0.113.10/32"]
trusted_cidr_blocks = ["0.0.0.0/0"]

app_port = 8080  # Change to 5000 (Flask), 3000 (Node), etc.
db_port  = 5432  # 5432 = PostgreSQL | 3306 = MySQL | 1433 = MSSQL

# Free tier cost controls — set true only when you're ready to incur charges
enable_nat_gateway = false   # NAT Gateway = ~$32/month (NOT free tier)
enable_flow_logs   = false   # CloudWatch ingestion cost (minimal but not free)

flow_log_retention_days = 30

common_tags = {
  Project     = "vpc-architecture"
  Environment = "production"
  ManagedBy   = "terraform"
  Owner       = "your-team"
}
