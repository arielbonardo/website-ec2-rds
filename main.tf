# Configuración del proveedor AWS
provider "aws" {
  region = "us-east-1"
}

# Variables
variable "vpc_cidr" {
  description = "CIDR para la VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR para la subred pública"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR para la subred privada"
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "Clase de instancia para RDS"
  default     = "db.t2.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  default     = "mywebdb"
}

variable "db_username" {
  description = "Usuario de la base de datos"
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Contraseña de la base de datos"
  default     = "Password123!"  # Para producción usar otro método como secretsmanager
  sensitive   = true
}

# Crear VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "web-vpc"
  }
}

# Crear Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "web-igw"
  }
}

# Crear subred pública
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "web-public-subnet"
  }
}

# Crear subred privada
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "us-east-1b"

  tags = {
    Name = "web-private-subnet"
  }
}

# Crear subred privada adicional para RDS (requerimiento de Multi-AZ)
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1c"

  tags = {
    Name = "web-private-subnet-2"
  }
}

# Tabla de rutas para subred pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "web-public-rt"
  }
}

# Asociación de la tabla de rutas con la subred pública
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Crear NAT Gateway para la subred privada
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "web-nat"
  }
}

# Tabla de rutas para subred privada
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "web-private-rt"
  }
}

# Asociación de la tabla de rutas con la subred privada
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# Grupo de seguridad para la instancia EC2
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Permitir tráfico HTTP, HTTPS y SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Para producción limitar a tu IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# Grupo de seguridad para la base de datos
resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "Permitir tráfico desde la instancia web a MySQL/PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306  # Para MySQL
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    from_port       = 5432  # Para PostgreSQL
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-sg"
  }
}

# Crear un grupo de subredes para RDS
resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_2.id]

  tags = {
    Name = "DB subnet group"
  }
}

# Crear instancia RDS
resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  multi_az               = false  # Cambiar a true para entornos de producción

  tags = {
    Name = "web-db"
  }
}

# Script de inicio para la instancia EC2
data "template_file" "user_data" {
  template = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx mysql-client
    echo "<!DOCTYPE html>
    <html>
    <head>
        <title>Mi Sitio Web Dinámico</title>
    </head>
    <body>
        <h1>Bienvenido a mi sitio web dinámico</h1>
        <p>Esta página está alojada en una instancia EC2 y conectada a RDS</p>
        <p>Endpoint de la base de datos: ${aws_db_instance.default.endpoint}</p>
    </body>
    </html>" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF
}

# Crear instancia EC2
resource "aws_instance" "web" {
  ami                    = "ami-0c55b159cbfafe1f0"  # Ubuntu 20.04 LTS (cambia según la región)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "my-key-pair"  # Asegúrate de tener este key pair creado
  user_data              = data.template_file.user_data.rendered

  tags = {
    Name = "web-server"
  }
}

# Outputs
output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_public_dns" {
  value = aws_instance.web.public_dns
}

output "rds_endpoint" {
  value = aws_db_instance.default.endpoint
}
