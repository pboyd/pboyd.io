# IAM user for GitHub Actions deployments
resource "aws_iam_user" "github_actions" {
  name = "github-actions-${var.domain_name}"

  tags = {
    Name        = "GitHub Actions Deployment User"
    Environment = "production"
  }
}

# Access key for GitHub Actions
resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

# IAM policy for deployment permissions
resource "aws_iam_policy" "github_actions_deploy" {
  name        = "github-actions-deploy-${var.domain_name}"
  description = "Permissions for GitHub Actions to deploy site"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SyncPermissions"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Sid      = "CloudFrontInvalidation"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.main.arn
      }
    ]
  })
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "github_actions" {
  user       = aws_iam_user.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}
