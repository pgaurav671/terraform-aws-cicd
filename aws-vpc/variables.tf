# ==============================================================================
# Variable Declarations
# ==============================================================================

variable "region" {
  description = "AWS region to deploy resources (e.g. ap-south-1, us-east-1)"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_name" {
  description = "Name prefix applied to all VPC resources"
  type        = string
  default     = "prod-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (must be /16 to /28)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets into (length must match subnet CIDR lists)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app-tier subnets — one per availability zone"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private DB-tier subnets — one per availability zone"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "trusted_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the bastion host. IMPORTANT: restrict this to your IP in production (e.g. [\"203.0.113.10/32\"])"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_port" {
  description = "Port the application tier listens on (e.g. 8080 for Node/Java, 5000 for Python)"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "Port the database listens on (5432 = PostgreSQL, 3306 = MySQL, 1433 = MSSQL)"
  type        = number
  default     = 5432
}

variable "enable_nat_gateway" {
  description = "Set to true to create a NAT Gateway (~$32/month, NOT free tier eligible). Set false to skip — private subnets lose outbound internet but the architecture is preserved."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Set to true to enable VPC Flow Logs to CloudWatch (small ingestion cost). Safe to disable for free tier demos."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC Flow Logs in CloudWatch (0 = never expire)"
  type        = number
  default     = 30
}

variable "common_tags" {
  description = "Tags applied to every resource for cost allocation and ownership tracking"
  type        = map(string)
  default = {
    Project     = "vpc-architecture"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
