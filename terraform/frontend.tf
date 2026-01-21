# Frontend Infrastructure - S3 + CloudFront for Artemis Platform Web Apps
# Hosts Flutter web applications as static sites

# S3 Buckets for each application frontend
resource "aws_s3_bucket" "frontend" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  bucket = "${var.environment}-${each.key}-frontend-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name        = "${var.environment}-${each.key}-frontend"
    Application = each.key
    Type        = "static-website"
  })
}

# S3 bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "frontend" {
  for_each = aws_s3_bucket.frontend

  bucket = each.value.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 bucket public access block - CloudFront will access via OAC
resource "aws_s3_bucket_public_access_block" "frontend" {
  for_each = aws_s3_bucket.frontend

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "frontend" {
  for_each = aws_s3_bucket.frontend

  bucket = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "frontend" {
  for_each = aws_s3_bucket.frontend

  bucket = each.value.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html" # SPA routing - return index.html for all routes
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  for_each = aws_s3_bucket.frontend

  name                              = "${var.environment}-${each.key}-frontend-oac"
  description                       = "OAC for ${each.key} frontend in ${var.environment}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution for each application
resource "aws_cloudfront_distribution" "frontend" {
  for_each = aws_s3_bucket.frontend

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${each.key} Frontend Distribution (${var.environment})"
  default_root_object = "index.html"
  price_class         = var.environment == "production" ? "PriceClass_100" : "PriceClass_100"

  aliases = var.frontend_certificate_arn != "" && var.domain_name != "" ? ["${each.key}.${var.domain_name}"] : []

  origin {
    domain_name              = each.value.bucket_regional_domain_name
    origin_id                = "S3-${each.value.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend[each.key].id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${each.value.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = var.environment == "production" ? 3600 : 60
    max_ttl                = var.environment == "production" ? 86400 : 300
    compress               = true
  }

  # Cache behavior for static assets (longer cache)
  ordered_cache_behavior {
    path_pattern     = "/assets/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${each.value.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400
    default_ttl            = 604800   # 1 week
    max_ttl                = 31536000 # 1 year
    compress               = true
  }

  # Custom error response for SPA routing
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.frontend_certificate_arn == ""
    acm_certificate_arn            = var.frontend_certificate_arn != "" ? var.frontend_certificate_arn : null
    ssl_support_method             = var.frontend_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(local.common_tags, {
    Name        = "${var.environment}-${each.key}-frontend-cdn"
    Application = each.key
  })
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "frontend" {
  for_each = aws_s3_bucket.frontend

  bucket = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${each.value.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend[each.key].arn
          }
        }
      }
    ]
  })
}
