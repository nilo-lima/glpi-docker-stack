output "vpc_id" {
  description = "ID da VPC criada."
  value       = aws_vpc.main.id
}

output "subnet_public_a_id" {
  description = "ID da subnet publica A (AZ-a). Aqui fica a EC2."
  value       = aws_subnet.public_a.id
}

output "subnet_public_b_id" {
  description = "ID da subnet publica B (AZ-b). Reservada para HA/ALB futuro."
  value       = aws_subnet.public_b.id
}

output "subnet_private_id" {
  description = "ID da subnet privada (AZ-a). Reservada para RDS/ElastiCache."
  value       = aws_subnet.private.id
}

output "vpc_cidr" {
  description = "CIDR block da VPC."
  value       = aws_vpc.main.cidr_block
}
