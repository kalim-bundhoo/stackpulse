#!/bin/bash
set -e

ROLE_NAME="GitHubActionsProductionDeployRole"
GITHUB_REPO="kalim-bundhoo/stackpulse"
AWS_ACCOUNT_ID="551504153839"

echo "=== 1. Checking AWS Account Identity ==="
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
echo "Target AWS Account ID: $CURRENT_ACCOUNT"

echo "=== 2. Setting up GitHub OIDC Provider ARN ==="
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
echo "Using OIDC Provider ARN: $OIDC_ARN"

echo "=== 3. Creating Trust Policy ==="
cat << POLICYEOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$OIDC_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
POLICYEOF

echo "=== 4. Creating or Updating IAM Role ==="
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "Role $ROLE_NAME exists. Updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document file://trust-policy.json
else
    echo "Creating role $ROLE_NAME..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://trust-policy.json
fi

echo "=== 5. Attaching Permissions Policy ==="
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

rm -f trust-policy.json
echo "=== Success! AWS OIDC role setup is complete for ${GITHUB_REPO} ==="
