############################
# Credentials
############################
# RDS rejects '/', '@', '"' and spaces in passwords, so the special set is restricted.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/db-credentials"
  description             = "MySQL credentials and endpoint for ${local.name}"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = var.secret_recovery_window_days
}

# Contains everything the application needs, so nothing sensitive is ever baked into
# user data, environment files or the repository.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    username = var.db_username
    password = random_password.db.result
  })
}

############################
# RDS MySQL (private subnets, Multi-AZ)
############################
resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.private_db[*].id

  tags = { Name = "${local.name}-db-subnets" }
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${local.name}-mysql-"
  family      = "mysql8.0"
  description = "MySQL parameters for ${local.name}"

  # Reject any connection that is not TLS-encrypted.
  parameter {
    name  = "require_secure_transport"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier = "${local.name}-mysql"

  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = var.db_backup_retention_days
  backup_window              = "21:00-22:00"
  maintenance_window         = "sun:22:30-sun:23:30"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["error", "slowquery"]

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${local.name}-final-snapshot"
  apply_immediately         = true

  tags = { Name = "${local.name}-mysql" }
}
