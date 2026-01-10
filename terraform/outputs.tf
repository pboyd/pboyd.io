output "nameservers" {
  description = "Route 53 nameservers to configure at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the main site (use for cache invalidation)"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name for the main site"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "site_bucket_name" {
  description = "S3 bucket name for site content"
  value       = aws_s3_bucket.site.id
}

output "site_url" {
  description = "URL of the deployed site"
  value       = "https://${var.domain_name}"
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "deployment_commands" {
  description = "Commands to deploy site updates"
  value = <<-EOT
    # Build the site
    hugo

    # Sync to S3
    aws s3 sync public/ s3://${aws_s3_bucket.site.id} --delete

    # Invalidate CloudFront cache
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths "/*"
  EOT
}
