# Terraform Infrastructure for pboyd.io

This directory contains Terraform configuration to deploy pboyd.io to AWS.

## Architecture

- **Route 53**: DNS management
- **S3**: Static file hosting (pboyd.io) and www redirect (www.pboyd.io)
- **CloudFront**: CDN with HTTPS
- **ACM**: Free SSL/TLS certificates
- **S3 + DynamoDB**: Remote state backend

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Domain pboyd.io registered (but DNS can be at another registrar)

## Initial Setup

### 1. Bootstrap Remote State

First, create the S3 bucket and DynamoDB table for Terraform state:

```bash
cd bootstrap
terraform init
terraform apply
```

Save the outputs, especially the backend configuration.

### 2. Configure Backend

Uncomment and update the backend configuration in `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "pboyd-io-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "pboyd-io-terraform-locks"
    encrypt        = true
  }
}
```

### 3. Deploy Main Infrastructure

```bash
cd ..  # Return to terraform/ directory
terraform init
terraform apply
```

Review the plan and type `yes` to create resources.

### 4. Update Nameservers

After Terraform completes, it will output the Route 53 nameservers:

```
nameservers = tolist([
  "ns-123.awsdns-12.com",
  "ns-456.awsdns-45.net",
  "ns-789.awsdns-78.org",
  "ns-012.awsdns-01.co.uk",
])
```

Update these nameservers at your domain registrar (where you purchased pboyd.io).

### 5. Wait for DNS Propagation

DNS changes can take up to 24-48 hours to propagate, though they often complete within minutes to hours. You can check status with:

```bash
dig NS pboyd.io
```

Once the nameservers match, the ACM certificate will validate automatically.

## Deploying Site Updates

After making changes to your Hugo site:

```bash
# Build the site
hugo

# Sync to S3 (from repository root)
aws s3 sync public/ s3://pboyd.io --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id <distribution-id> --paths "/*"
```

The distribution ID is available in the Terraform outputs:

```bash
terraform output cloudfront_distribution_id
```

## Useful Commands

```bash
# View all outputs
terraform output

# Get deployment commands
terraform output deployment_commands

# Check state
terraform show

# Destroy everything (careful!)
terraform destroy
```

## Cost Estimate

Expected monthly costs for low traffic:
- Route 53 hosted zone: $0.50
- S3 storage (1GB): $0.023
- CloudFront (10GB transfer): $0.85
- ACM certificate: Free

**Total: ~$1.40/month**

## Troubleshooting

### Certificate Validation Stuck

If certificate validation hangs, ensure nameservers are updated at your registrar. Check with:

```bash
dig NS pboyd.io
```

### CloudFront 403 Errors

If you see 403 errors, ensure:
1. Content exists in the S3 bucket
2. CloudFront OAC policy is applied to the bucket
3. index.html exists in the bucket root

### State Lock Issues

If you get a state lock error:

```bash
# List locks
aws dynamodb scan --table-name pboyd-io-terraform-locks

# Force unlock (use with caution)
terraform force-unlock <lock-id>
```
