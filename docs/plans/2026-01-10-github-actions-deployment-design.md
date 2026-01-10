# GitHub Actions Deployment Design

## Overview

Deploy the Hugo static site to AWS S3 with CloudFront cache invalidation on every push to the main branch.

## Requirements

- Automatically build and deploy on push to main
- Sync built files to S3 bucket (pboyd.io)
- Invalidate CloudFront cache after deployment
- Use IAM access keys for AWS authentication
- Keep workflow simple without extra features

## Workflow Configuration

**File location**: `.github/workflows/deploy.yml`

**Trigger**: Push to main branch

**Runner**: ubuntu-latest

**Permissions**: `contents: read` (checkout only)

## Environment Variables

- `HUGO_VERSION`: 0.121.1 (extended LTS)
- `AWS_REGION`: us-east-1

## Required GitHub Secrets

1. `AWS_ACCESS_KEY_ID` - IAM user access key
2. `AWS_SECRET_ACCESS_KEY` - IAM user secret key
3. `CLOUDFRONT_DISTRIBUTION_ID` - CloudFront distribution ID from Terraform

## IAM Permissions Required

The IAM user needs permissions for:
- `s3:PutObject` on arn:aws:s3:::pboyd.io/*
- `s3:DeleteObject` on arn:aws:s3:::pboyd.io/*
- `s3:ListBucket` on arn:aws:s3:::pboyd.io
- `cloudfront:CreateInvalidation` on the distribution ARN

## Workflow Steps

1. **Checkout repository**
   - Action: `actions/checkout@v4`
   - Config: `submodules: recursive` for theme support

2. **Setup Hugo**
   - Action: `peaceiris/actions-hugo@v2`
   - Version: `${{ env.HUGO_VERSION }}`
   - Extended: true (SCSS/SASS support)

3. **Build site**
   - Command: `hugo --minify --baseURL https://pboyd.io/`
   - Output directory: `public/`

4. **Configure AWS credentials**
   - Action: `aws-actions/configure-aws-credentials@v4`
   - Uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets

5. **Sync to S3**
   - Command: `aws s3 sync public/ s3://pboyd.io/ --delete --size-only`
   - `--delete`: Remove files not in source
   - `--size-only`: Skip unchanged files

6. **Invalidate CloudFront**
   - Command: `aws cloudfront create-invalidation --distribution-id ${{ secrets.CLOUDFRONT_DISTRIBUTION_ID }} --paths "/*"`
   - Invalidates all paths for immediate visibility

## Error Handling

Each step fails the workflow on non-zero exit code. CloudFront invalidation runs last, so failed S3 syncs won't create invalidations for broken deployments.

## Future Considerations

Potential enhancements not included in initial implementation:
- OIDC authentication (more secure than access keys)
- Concurrency control for simultaneous pushes
- Deployment status comments on commits
- Build artifact caching
- Path-specific CloudFront invalidations
