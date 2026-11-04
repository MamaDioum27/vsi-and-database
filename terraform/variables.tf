variable "region" {
  description = "Région AWS"
  type        = string
  default     = "eu-north-1"
}

variable "db_password" {
  description = "Mot de passe PostgreSQL (passé via TF_VAR_db_password, jamais en dur)"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Utilisateur administrateur PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "db_name" {
  description = "Nom de la base créée sur RDS"
  type        = string
  default     = "appdb"
}

variable "ssh_public_key_path" {
  description = "Chemin de la clé SSH publique installée sur les VMs"
  type        = string
  default     = "~/.ssh/tp-lb.pub"
}

variable "repo_url" {
  description = "Dépôt Git contenant app.py et requirements.txt"
  type        = string
  default     = "https://github.com/oumarkouf/vsi-and-database.git"
}

variable "instance_type" {
  description = "Type d'instance EC2 (éligible à l'offre gratuite)"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "Classe d'instance RDS (éligible à l'offre gratuite)"
  type        = string
  default     = "db.t3.micro"
}

variable "vm_count" {
  description = "Nombre de VMs derrière le load balancer"
  type        = number
  default     = 2
}
