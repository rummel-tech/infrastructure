# Secrets Manager Rotation for Artemis Platform
# Covers: (1) database master password, (2) JWT RSA key pair

# ---------------------------------------------------------------------------
# IAM execution role shared by rotation Lambda functions
# ---------------------------------------------------------------------------

resource "aws_iam_role" "secrets_rotation_lambda" {
  name        = "${var.environment}-secrets-rotation-lambda-role"
  description = "Execution role for Secrets Manager rotation Lambda functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.environment}-secrets-rotation-lambda-role"
  })
}

resource "aws_iam_role_policy" "secrets_rotation_lambda" {
  name = "${var.environment}-secrets-rotation-lambda-policy"
  role = aws_iam_role.secrets_rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda stub for DB master password rotation
#
# NOTE: This stub uses a placeholder ZIP. Replace the filename / s3_bucket +
# s3_key attributes with your actual rotation-function deployment artifact
# before enabling rotation. The Lambda must implement the four Secrets Manager
# rotation lifecycle events: createSecret, setSecret, testSecret, finishSecret.
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "rotate_secret" {
  function_name = "${var.environment}-rotate-db-password"
  description   = "Rotates the Artemis RDS master password in Secrets Manager"

  # Replace with your actual deployment package (S3 or local ZIP).
  # Example using S3:
  #   s3_bucket = "your-deployment-bucket"
  #   s3_key    = "lambdas/rotate-db-password.zip"
  filename = "${path.module}/placeholder-rotate-db-password.zip"

  role    = aws_iam_role.secrets_rotation_lambda.arn
  handler = "handler.lambda_handler"
  runtime = "python3.12"
  timeout = 30

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-rotate-db-password"
    Purpose = "secrets-rotation"
  })

  lifecycle {
    # Ignore source-code changes so that CI/CD deployments of this Lambda
    # do not cause Terraform to redeploy unrelated infrastructure.
    ignore_changes = [filename, last_modified]
  }
}

# Allow Secrets Manager to invoke the rotation Lambda
resource "aws_lambda_permission" "secrets_manager_invoke_rotate_db" {
  statement_id  = "SecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
}

# ---------------------------------------------------------------------------
# DB master password rotation
#
# NOTE: aws_secretsmanager_secret.db_master_password is not yet defined in
# this Terraform codebase. The existing DB credentials secret is named
# aws_secretsmanager_secret.db_credentials (see rds.tf). Uncomment and
# update the secret_id below once a dedicated db_master_password secret
# resource is added, or replace the reference with db_credentials if you
# want to rotate that combined-credentials secret instead.
# ---------------------------------------------------------------------------

# resource "aws_secretsmanager_secret_rotation" "db_password" {
#   secret_id           = aws_secretsmanager_secret.db_master_password.id
#   rotation_lambda_arn = aws_lambda_function.rotate_secret.arn
#
#   rotation_rules {
#     automatically_after_days = 30
#   }
# }

# ---------------------------------------------------------------------------
# JWT RSA key-pair rotation
#
# The Artemis auth service issues tokens signed with an RSA private key. This
# EventBridge rule fires every 90 days and triggers a Lambda that generates a
# new RSA-2048 key pair, stores the private key in Secrets Manager, publishes
# the new public key to a well-known endpoint (or SSM Parameter Store), and
# then gracefully retires the previous key after a configurable overlap window
# so that in-flight tokens remain valid during the transition.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "jwt_key_rotation" {
  name                = "${var.environment}-jwt-key-rotation"
  description         = "Triggers JWT RSA key-pair rotation every 90 days for Artemis tokens"
  schedule_expression = "rate(90 days)"

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-jwt-key-rotation"
    Purpose = "jwt-key-rotation"
  })
}

# Lambda stub for JWT key-pair rotation
resource "aws_lambda_function" "rotate_jwt_keys" {
  function_name = "${var.environment}-rotate-jwt-keys"
  description   = "Rotates the RSA private/public key pair used for Artemis JWT token signing"

  # Replace with your actual deployment package.
  filename = "${path.module}/placeholder-rotate-jwt-keys.zip"

  role    = aws_iam_role.secrets_rotation_lambda.arn
  handler = "handler.lambda_handler"
  runtime = "python3.12"
  timeout = 60

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
      # Set to the Secrets Manager secret names / ARNs that hold the JWT keys.
      # Example: "${var.environment}/auth/jwt_private_key"
      JWT_PRIVATE_KEY_SECRET_PREFIX = "${var.environment}"
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-rotate-jwt-keys"
    Purpose = "jwt-key-rotation"
  })

  lifecycle {
    ignore_changes = [filename, last_modified]
  }
}

resource "aws_cloudwatch_event_target" "jwt_key_rotation" {
  rule      = aws_cloudwatch_event_rule.jwt_key_rotation.name
  target_id = "RotateJWTKeys"
  arn       = aws_lambda_function.rotate_jwt_keys.arn
}

resource "aws_lambda_permission" "eventbridge_invoke_rotate_jwt" {
  statement_id  = "EventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_jwt_keys.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.jwt_key_rotation.arn
}
