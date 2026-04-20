terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment after running bootstrap/
  # backend "s3" {
  #   bucket         = "YOUR-STATE-BUCKET-NAME"
  #   key            = "project-01/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "YOUR-LOCK-TABLE-NAME"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── S3 Bucket ──────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "website" {
  bucket = "${var.project_name}-${var.environment}-website-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = false # set to true in production
  }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Origin Access Control ──────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-${var.environment}-oac"
  description                       = "OAC for ${var.project_name} website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── S3 Bucket Policy — allow CloudFront only ───────────────────────────────────

data "aws_iam_policy_document" "website_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontAccess"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket     = aws_s3_bucket.website.id
  policy     = data.aws_iam_policy_document.website_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.website]
}

# ── Sample HTML Files ──────────────────────────────────────────────────────────

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  content_type = "text/html"

  content = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>${var.project_name}</title>
      <style>
        body { font-family: -apple-system, sans-serif; display: flex; justify-content: center;
               align-items: center; min-height: 100vh; margin: 0; background: #0f172a; color: #e2e8f0; }
        .card { text-align: center; padding: 2rem; }
        h1 { font-size: 2.5rem; color: #38bdf8; }
        p  { color: #94a3b8; }
        .badge { background: #1e293b; border: 1px solid #334155; padding: 0.5rem 1rem;
                 border-radius: 9999px; font-size: 0.875rem; display: inline-block; margin-top: 1rem; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>${var.project_name}</h1>
        <p>Deployed with Terraform + CloudFront</p>
        <div class="badge">Environment: ${var.environment}</div>
      </div>
    </body>
    </html>
  HTML

  etag = md5("${var.project_name}-${var.environment}-index")
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.website.id
  key          = "error.html"
  content_type = "text/html"

  content = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>Page Not Found</title>
      <style>
        body { font-family: -apple-system, sans-serif; display: flex; justify-content: center;
               align-items: center; min-height: 100vh; margin: 0; background: #0f172a; color: #e2e8f0; }
        .card { text-align: center; }
        h1 { font-size: 4rem; color: #f87171; margin: 0; }
        p  { color: #94a3b8; }
        a  { color: #38bdf8; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>404</h1>
        <p>Page not found</p>
        <a href="/">Go home</a>
      </div>
    </body>
    </html>
  HTML

  etag = md5("${var.project_name}-${var.environment}-error")
}

# ── CloudFront Distribution ────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name}-${var.environment} website"
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.website.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # Custom 404 → error.html
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
  }

  # Custom 403 (S3 access denied) → also show 404
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # Uncomment to use custom domain:
    # acm_certificate_arn      = var.acm_certificate_arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_s3_bucket_policy.website]
}

# ── Data Sources ───────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}
