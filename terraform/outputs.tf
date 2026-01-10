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
  value       = <<-EOT
    # Build the site
    hugo

    # Sync to S3
    aws s3 sync public/ s3://${aws_s3_bucket.site.id} --delete

    # Invalidate CloudFront cache
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths "/*"
  EOT
}

output "github_actions_access_key_id" {
  description = "Access key ID for GitHub Actions (add to GitHub secrets as AWS_ACCESS_KEY_ID)"
  value       = aws_iam_access_key.github_actions.id
  sensitive   = true
}

output "github_actions_secret_access_key" {
  description = "Secret access key for GitHub Actions (add to GitHub secrets as AWS_SECRET_ACCESS_KEY)"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}
