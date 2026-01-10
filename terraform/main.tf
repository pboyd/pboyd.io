# Route 53 Hosted Zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name        = var.domain_name
    Environment = "production"
  }
}

# ACM Certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = var.domain_name
    Environment = "production"
  }
}

# DNS validation records for ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# S3 bucket for site content
resource "aws_s3_bucket" "site" {
  bucket = var.domain_name

  tags = {
    Name        = var.domain_name
    Environment = "production"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control for main site
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = var.domain_name
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Function to rewrite directory requests to index.html
resource "aws_cloudfront_function" "url_rewrite" {
  name    = "${replace(var.domain_name, ".", "-")}-url-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite directory requests to index.html"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Check if URI ends with '/'
      if (uri.endsWith('/')) {
        request.uri += 'index.html';
      }
      // Check if URI has no extension (likely a directory)
      else if (!uri.includes('.')) {
        request.uri += '/index.html';
      }

      return request;
    }
  EOT
}

# CloudFront distribution for main site
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "S3-${var.domain_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.domain_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.url_rewrite.arn
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.main.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = var.domain_name
    Environment = "production"
  }

  depends_on = [aws_acm_certificate_validation.main]
}

# S3 bucket policy to allow CloudFront OAC access
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

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
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# Route 53 A record for apex domain
resource "aws_route53_record" "main" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# MX Records for ProtonMail
resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 3600

  records = [
    "10 mail.protonmail.ch",
    "20 mailsec.protonmail.ch",
  ]
}

# DKIM CNAME Records for ProtonMail
resource "aws_route53_record" "dkim_protonmail" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "protonmail._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 3600
  records = ["protonmail.domainkey.dxxbmllqo53yoiafr7efoptflfoovycdf5bcwopjcdafnn5pqctnq.domains.proton.ch"]
}

resource "aws_route53_record" "dkim_protonmail2" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "protonmail2._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 3600
  records = ["protonmail2.domainkey.dxxbmllqo53yoiafr7efoptflfoovycdf5bcwopjcdafnn5pqctnq.domains.proton.ch"]
}

resource "aws_route53_record" "dkim_protonmail3" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "protonmail3._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 3600
  records = ["protonmail3.domainkey.dxxbmllqo53yoiafr7efoptflfoovycdf5bcwopjcdafnn5pqctnq.domains.proton.ch"]
}

# TXT Records (combined for apex domain)
resource "aws_route53_record" "txt" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 3600

  records = [
    "v=spf1 include:_spf.protonmail.ch include:simplelogin.co ~all",
    "protonmail-verification=dcf68795367174079b0606eea3e28d6b41031f41",
    "sl-verification=utodujkdumupufjnupjdtawadriryy",
    "google-site-verification=qUnOJYnNzKIUABU5-NLYVMGFv2526X4FqwTv7sB28CY",
  ]
}

# DMARC Record
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=none"]
}
