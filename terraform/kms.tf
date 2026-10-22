# One customer-managed key for RDS storage, the application S3 bucket and Secrets Manager.
# (EBS uses the AWS-managed aws/ebs key: a CMK there requires extra key-policy grants for the
# Auto Scaling service-linked role, which adds risk without adding value for this project.)
resource "aws_kms_key" "main" {
  description             = "${local.name} data encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = { Name = "${local.name}-key" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}
