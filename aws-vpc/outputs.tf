# ==============================================================================
# Outputs — values exposed after `terraform apply`
# Use these as inputs when connecting other modules (e.g. ECS, RDS, EC2)
# ==============================================================================

# --- VPC ---
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# --- Subnets ---
output "public_subnet_ids" {
  description = "IDs of the public subnets (one per AZ) — use for ALB, bastion, NAT"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of the private app subnets (one per AZ) — use for EC2, ECS, Lambda"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of the private DB subnets (one per AZ) — use for RDS, ElastiCache"
  value       = aws_subnet.private_db[*].id
}

# --- Gateways ---
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (empty when enable_nat_gateway = false)"
  value       = var.enable_nat_gateway ? aws_nat_gateway.nat[0].id : null
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway (empty when enable_nat_gateway = false)"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}

# --- Route Tables ---
output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_app_route_table_id" {
  description = "ID of the private app route table"
  value       = aws_route_table.private_app.id
}

output "private_db_route_table_id" {
  description = "ID of the private DB route table"
  value       = aws_route_table.private_db.id
}

# --- Security Groups ---
output "bastion_sg_id" {
  description = "Security Group ID for the bastion host"
  value       = aws_security_group.bastion.id
}

output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security Group ID for the app tier"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security Group ID for the database tier"
  value       = aws_security_group.db.id
}

# --- Flow Logs ---
output "flow_log_group_name" {
  description = "CloudWatch Log Group name (empty when enable_flow_logs = false)"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}
