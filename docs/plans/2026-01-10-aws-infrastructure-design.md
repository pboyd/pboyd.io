# AWS Infrastructure Design for pboyd.io

## Overview

This document describes the infrastructure design for deploying pboyd.io, a Hugo static site, to AWS using Terraform.

## Architecture

The infrastructure consists of Route 53 DNS, S3 storage, CloudFront CDN, and ACM certificates.

### Route 53

Route 53 manages DNS for pboyd.io. After Terraform creates the hosted zone, you must update nameservers at your current registrar to point to AWS. A-record aliases point to CloudFront distributions.

### S3 Buckets

Two buckets serve the site:

**Primary bucket (pboyd.io)**: Stores Hugo site files from the public/ directory. The bucket remains private. CloudFront accesses it via Origin Access Control (OAC). A bucket policy grants CloudFront read access.

**Redirect bucket (www.pboyd.io)**: Redirects www.pboyd.io to https://pboyd.io. The bucket uses S3 website hosting with redirect-all configuration pointing to https://pboyd.io. Public read access is required for S3's website feature to work.

### CloudFront Distributions

Two distributions deliver content:

**Primary distribution**: Serves the S3 bucket via OAC. Sets index.html as the default root object. Routes 404 errors to 404.html for Hugo's custom error page. Uses PriceClass_100 (US/EU/Israel) to minimize costs while covering most users. Redirects HTTP to HTTPS via viewer protocol policy.

**Redirect distribution**: Serves the S3 website endpoint (not the bucket itself) to preserve S3's redirect behavior. Simpler configuration since it passes through redirects.

### ACM Certificate

A single certificate covers both pboyd.io and *.pboyd.io. DNS validation uses Route 53 records that Terraform creates automatically. The certificate must reside in us-east-1 for CloudFront compatibility. Terraform waits for validation to complete.

## Terraform Organization

The Terraform code lives in terraform/ at the repository root:

```
terraform/
├── bootstrap/          # State backend infrastructure
│   ├── main.tf
│   └── outputs.tf
├── main.tf            # Primary infrastructure
├── variables.tf       # Input variables
├── outputs.tf         # Useful outputs
├── backend.tf         # S3 backend configuration
└── providers.tf       # AWS provider setup
```

### Bootstrap Process

First, apply bootstrap/ with local state to create the S3 bucket and DynamoDB table for remote state. Then configure backend.tf with the S3 bucket name, run `terraform init` to migrate state to S3, and apply the main infrastructure.

### Provider Configuration

The AWS provider uses version ~> 5.0 and defaults to us-east-1 (required for ACM certificates). Route 53 operates globally regardless of region.

### Variables

The domain name defaults to "pboyd.io" but remains parameterized for flexibility.

## Deployment

### Initial Setup

1. Apply bootstrap: `cd terraform/bootstrap && terraform init && terraform apply`
2. Configure backend.tf with bootstrap outputs
3. Initialize main Terraform: `cd .. && terraform init`
4. Apply infrastructure: `terraform apply`
5. Update nameservers at your registrar using Terraform outputs
6. Wait for DNS propagation (usually under 24 hours)
7. ACM validates automatically via DNS after nameserver update

### Site Updates

Build the site with `hugo`, sync to S3 with `aws s3 sync public/ s3://pboyd.io --delete`, and invalidate CloudFront cache with `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`.

### State Management

The S3 state bucket enables versioning for recovery. The DynamoDB table prevents concurrent modifications. Keep bootstrap/terraform.tfstate backed up - you need it to manage the state infrastructure.

## Security

CloudFront Origin Access Control prevents direct S3 access. ACM provides free, auto-renewing certificates. S3 bucket versioning protects against accidental deletions during sync operations.

## Cost Estimate

Expected monthly costs for low traffic:
- Route 53 hosted zone: $0.50
- S3 storage (1GB): $0.023
- CloudFront (10GB transfer): $0.85
- ACM certificate: Free

Total: ~$1.40/month

Costs increase with traffic. CloudFront charges vary by region and transfer volume.
