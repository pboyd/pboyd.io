# GitHub Actions Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automate Hugo site builds and deployments to S3 with CloudFront invalidation on push to main branch.

**Architecture:** GitHub Actions workflow triggers on main branch pushes, builds Hugo site, syncs to S3, and invalidates CloudFront. IAM user with minimal permissions handles AWS authentication.

**Tech Stack:** GitHub Actions, Hugo 0.121.1, AWS CLI, Terraform (for IAM provisioning)

---

## Task 1: Create IAM User for GitHub Actions

**Files:**
- Create: `terraform/github-actions-iam.tf`
- Modify: `terraform/outputs.tf` (append new outputs)

**Step 1: Create IAM user and policy in Terraform**

Create `terraform/github-actions-iam.tf`:

```hcl
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
```

**Step 2: Add outputs for IAM credentials**

Add to `terraform/outputs.tf`:

```hcl
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
```

**Step 3: Initialize and plan Terraform changes**

Run from terraform directory:

```bash
cd terraform
terraform init
terraform plan
```

Expected: Plan shows 3 resources to add (IAM user, access key, policy, attachment)

**Step 4: Apply Terraform changes**

```bash
terraform apply
```

Expected: Resources created successfully

**Step 5: Capture IAM credentials**

```bash
terraform output -raw github_actions_access_key_id
terraform output -raw github_actions_secret_access_key
```

Expected: Access key ID and secret key printed (save these securely for GitHub secrets setup)

**Step 6: Commit Terraform changes**

```bash
cd ..
git add terraform/github-actions-iam.tf terraform/outputs.tf
git commit -m "Add IAM user for GitHub Actions deployments"
```

---

## Task 2: Create GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

**Step 1: Create .github/workflows directory**

```bash
mkdir -p .github/workflows
```

**Step 2: Create workflow file**

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS

on:
  push:
    branches:
      - main

env:
  HUGO_VERSION: 0.121.1
  AWS_REGION: us-east-1

permissions:
  contents: read

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v2
        with:
          hugo-version: ${{ env.HUGO_VERSION }}
          extended: true

      - name: Build site
        run: hugo --minify --baseURL https://pboyd.io/

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Sync to S3
        run: |
          aws s3 sync public/ s3://pboyd.io/ --delete --size-only

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id ${{ secrets.CLOUDFRONT_DISTRIBUTION_ID }} \
            --paths "/*"
```

**Step 3: Verify workflow syntax**

```bash
cat .github/workflows/deploy.yml
```

Expected: Valid YAML with proper indentation

**Step 4: Commit workflow file**

```bash
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions deployment workflow"
```

---

## Task 3: Configure GitHub Repository Secrets

**Manual Steps (document in commit message or PR):**

**Step 1: Get CloudFront distribution ID**

From terraform directory:

```bash
cd terraform
terraform output -raw cloudfront_distribution_id
```

Expected: Distribution ID like `E1234ABCD5678`

**Step 2: Navigate to GitHub repository settings**

1. Go to https://github.com/[username]/pboyd.io/settings/secrets/actions
2. Click "New repository secret"

**Step 3: Add AWS_ACCESS_KEY_ID secret**

- Name: `AWS_ACCESS_KEY_ID`
- Value: [from Task 1, Step 5]
- Click "Add secret"

**Step 4: Add AWS_SECRET_ACCESS_KEY secret**

- Name: `AWS_SECRET_ACCESS_KEY`
- Value: [from Task 1, Step 5]
- Click "Add secret"

**Step 5: Add CLOUDFRONT_DISTRIBUTION_ID secret**

- Name: `CLOUDFRONT_DISTRIBUTION_ID`
- Value: [from Step 1 of this task]
- Click "Add secret"

**Step 6: Create documentation commit**

Create `docs/github-actions-setup.md`:

```markdown
# GitHub Actions Setup

## Required Secrets

Configure these in Repository Settings > Secrets and variables > Actions:

1. `AWS_ACCESS_KEY_ID` - From `terraform output github_actions_access_key_id`
2. `AWS_SECRET_ACCESS_KEY` - From `terraform output github_actions_secret_access_key`
3. `CLOUDFRONT_DISTRIBUTION_ID` - From `terraform output cloudfront_distribution_id`

## Workflow Trigger

Workflow runs automatically on push to main branch.

## Manual Trigger

Not supported in current configuration. To deploy manually, push to main or modify workflow to add `workflow_dispatch` trigger.
```

```bash
git add docs/github-actions-setup.md
git commit -m "Add GitHub Actions setup documentation"
```

---

## Task 4: Test Deployment Workflow

**Step 1: Push to main branch**

```bash
git push origin main
```

Expected: GitHub Actions workflow triggers

**Step 2: Monitor workflow execution**

```bash
gh run watch
```

Or visit: https://github.com/[username]/pboyd.io/actions

Expected: Workflow completes successfully with all steps green

**Step 3: Verify S3 sync**

```bash
aws s3 ls s3://pboyd.io/ --recursive | head -20
```

Expected: Files from public/ directory present in bucket

**Step 4: Verify site loads**

```bash
curl -I https://pboyd.io/
```

Expected: HTTP 200 response with content

**Step 5: Verify CloudFront invalidation**

```bash
aws cloudfront list-invalidations --distribution-id $(cd terraform && terraform output -raw cloudfront_distribution_id)
```

Expected: Recent invalidation with status "Completed" or "InProgress"

**Step 6: Create completion commit**

```bash
git commit --allow-empty -m "Verify GitHub Actions deployment workflow"
```

---

## Post-Implementation Checklist

- [ ] IAM user created with minimal permissions
- [ ] GitHub secrets configured (3 total)
- [ ] Workflow file committed to repository
- [ ] Test deployment succeeds
- [ ] Site accessible at https://pboyd.io/
- [ ] CloudFront cache invalidation working
- [ ] Documentation updated

## Rollback Plan

If deployment fails:

1. Disable workflow: Rename `.github/workflows/deploy.yml` to `.github/workflows/deploy.yml.disabled`
2. Deploy manually using commands from `terraform output deployment_commands`
3. Debug workflow in separate branch before re-enabling

## Security Notes

- Access keys are sensitive - never commit to repository
- IAM user has minimal permissions (S3 write, CloudFront invalidate only)
- Consider rotating access keys periodically
- Consider migrating to OIDC authentication for better security

## Future Enhancements

- Add workflow concurrency control
- Add deployment status comments
- Implement path-specific CloudFront invalidations
- Add build caching for faster runs
- Migrate to OIDC authentication
