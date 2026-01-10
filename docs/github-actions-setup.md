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
