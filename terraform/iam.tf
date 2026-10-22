data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager access: no SSH keys, no port 22, no bastion host.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least privilege: exactly one secret, one key, and two prefixes of one bucket.
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db.arn]
  }

  statement {
    sid       = "UseProjectKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid       = "ReadReleaseArtifacts"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app.arn}/artifacts/*"]
  }

  statement {
    sid       = "ReadWriteApplicationData"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.app.arn}/data/*"]
  }

  statement {
    sid       = "ListApplicationPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["artifacts/*", "data/*"]
    }
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${local.name}-app-access"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.app.name
}
