terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "tp-lb-https"
    }
  }
}

# ---------------------------------------------------------------------------
# Données : IP de l'admin, VPC et sous-réseaux par défaut, AMI
# ---------------------------------------------------------------------------

# IP publique de la machine qui lance Terraform (le Codespace) -> seule autorisée en SSH
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  admin_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

data "aws_vpc" "default" {
  default = true
}

# Un sous-réseau par défaut par zone de disponibilité
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  subnet_ids = sort(data.aws_subnets.default.ids)
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# Load balancer : 443 et 80 ouverts à Internet
resource "aws_security_group" "alb" {
  name        = "tp-alb-sg"
  description = "ALB: HTTPS/HTTP depuis Internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (redirection vers HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VMs : 8080 uniquement depuis l'ALB, SSH uniquement depuis l'IP de l'admin
resource "aws_security_group" "vm" {
  name        = "tp-vm-sg"
  description = "VMs: 8080 depuis le LB, SSH depuis admin"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "App depuis le load balancer"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Base : 5432 uniquement depuis les VMs
resource "aws_security_group" "db" {
  name        = "tp-db-sg"
  description = "RDS: PostgreSQL depuis les VMs uniquement"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL depuis les VMs"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.vm.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Base de données managée (PaaS)
# ---------------------------------------------------------------------------

resource "aws_db_instance" "db" {
  identifier             = "app-postgres"
  engine                 = "postgres"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}

# ---------------------------------------------------------------------------
# VMs (IaaS) x2, dans deux zones différentes
# ---------------------------------------------------------------------------

resource "aws_key_pair" "admin" {
  key_name   = "tp-lb-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_instance" "app" {
  count = var.vm_count

  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_ids[count.index % length(local.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.vm.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true

  # Installation et déploiement de l'app au premier démarrage
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname = "vm-${count.index + 1}"
    repo_url = var.repo_url
    db_host  = aws_db_instance.db.address
    db_port  = aws_db_instance.db.port
    db_name  = var.db_name
    db_user  = var.db_username
    db_pass  = var.db_password
  })
  user_data_replace_on_change = true

  tags = {
    Name = "vm-${count.index + 1}"
  }
}

# ---------------------------------------------------------------------------
# Certificat TLS auto-signé (lab uniquement) importé dans ACM
# ---------------------------------------------------------------------------

resource "tls_private_key" "lb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "lb" {
  private_key_pem = tls_private_key.lb.private_key_pem

  # ACM/ALB exige un nom de domaine complet (FQDN)
  subject {
    common_name = "lab-lb.example.com"
  }
  dns_names = ["lab-lb.example.com", aws_lb.app.dns_name]

  validity_period_hours = 720 # 30 jours
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "lb" {
  private_key      = tls_private_key.lb.private_key_pem
  certificate_body = tls_self_signed_cert.lb.cert_pem
}

# ---------------------------------------------------------------------------
# Load balancer HTTPS (ALB)
# ---------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "tp-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "app" {
  name                 = "tp-app-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.default.id
  deregistration_delay = 10

  health_check {
    path                = "/health"
    port                = "8080"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count = var.vm_count

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8080
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.lb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
