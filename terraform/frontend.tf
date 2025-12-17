# Frontend Infrastructure - S3 + CloudFront for Workout Planner Web App
# This hosts the Flutter web application as a static site

# S3 Bucket for static website hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "${var.app_name}-frontend-${var.environment}"

  tags = merge(var.tags, {
    Name = "${var.app_name}-frontend"
    Type = "static-website"
  })
}

# S3 bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 bucket public access block - CloudFront will access via OAC
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"  # SPA routing - return index.html for all routes
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.app_name}-frontend-oac"
  description                       = "OAC for ${var.app_name} frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.app_name} Frontend Distribution"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"  # US, Canada, Europe only for cost savings

  aliases = var.frontend_domain_name != "" ? [var.frontend_domain_name] : []

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
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
    cloudfront_default_certificate = var.frontend_certificate_arn == "" ? true : false
    acm_certificate_arn            = var.frontend_certificate_arn != "" ? var.frontend_certificate_arn : null
    ssl_support_method             = var.frontend_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    Name = "${var.app_name}-frontend-cdn"
  })
}

# S3 bucket policy to allow CloudFront access
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# Outputs
output "frontend_bucket_name" {
  description = "S3 bucket name for frontend assets"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "S3 bucket ARN for frontend assets"
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_url" {
  description = "Frontend URL"
  value       = var.frontend_domain_name != "" ? "https://${var.frontend_domain_name}" : "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
