output "instance_id" {
  description = "ID da instancia EC2."
  value       = aws_instance.glpi.id
}

output "public_ip" {
  description = "Elastic IP publico da EC2. Use este IP para configurar os A records no DNS."
  value       = aws_eip.glpi.public_ip
}

output "private_ip" {
  description = "IP privado da EC2 dentro da VPC."
  value       = aws_instance.glpi.private_ip
}

output "ec2_role_arn" {
  description = "ARN do IAM Role da EC2 (necessario para a bucket policy do S3)."
  value       = aws_iam_role.ec2.arn
}

output "ami_id" {
  description = "ID da AMI Debian 12 usada."
  value       = data.aws_ami.debian_12.id
}

output "ami_name" {
  description = "Nome da AMI Debian 12 usada."
  value       = data.aws_ami.debian_12.name
}

output "ssh_command" {
  description = "Comando SSH para conectar na instancia (substitua o path da chave privada)."
  value       = "ssh -i ~/.ssh/id_rsa admin@${aws_eip.glpi.public_ip}"
}
