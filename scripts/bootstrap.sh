#!/usr/bin/env bash
# scripts/bootstrap.sh
#
# One-time setup: creates the S3 bucket and DynamoDB table used by Terraform
# for remote state storage and state locking.
#
# Prerequisites:
#   - AWS CLI configured with credentials that have S3 + DynamoDB + KMS permissions
#   - Run this ONCE before your first `terraform init`
#
# Usage:
#   chmod +x scripts/bootstrap.sh
#   AWS_PROFILE=my-admin-profile ./scripts/bootstrap.sh [prod|dev]

set -euo pipefail

ENVIRONMENT="${1:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

BUCKET_NAME="secure-app-tfstate-${ACCOUNT_ID}-${ENVIRONMENT}"
DYNAMO_TABLE="secure-app-tfstate-lock-${ENVIRONMENT}"
KMS_ALIAS="alias/secure-app-tfstate-${ENVIRONMENT}"

echo "╔══════════════════════════════════════════════╗"
echo "║   Terraform State Backend Bootstrap          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Environment : ${ENVIRONMENT}"
echo "  Region      : ${AWS_REGION}"
echo "  Account     : ${ACCOUNT_ID}"
echo "  Bucket      : ${BUCKET_NAME}"
echo "  DynamoDB    : ${DYNAMO_TABLE}"
echo ""

# ─────────────────────────────────────────────
# KMS key for state encryption
# ─────────────────────────────────────────────
echo "▶ Creating KMS key for state encryption..."
KMS_KEY_ID=$(aws kms create-key \
  --description "Terraform state encryption — ${ENVIRONMENT}" \
  --region "${AWS_REGION}" \
  --query 'KeyMetadata.KeyId' \
  --output text)

aws kms enable-key-rotation --key-id "${KMS_KEY_ID}" --region "${AWS_REGION}"

aws kms create-alias \
  --alias-name "${KMS_ALIAS}" \
  --target-key-id "${KMS_KEY_ID}" \
  --region "${AWS_REGION}" 2>/dev/null || echo "  KMS alias already exists, skipping."

echo "  ✓ KMS key: ${KMS_KEY_ID}"

# ─────────────────────────────────────────────
# S3 bucket for state files
# ─────────────────────────────────────────────
echo "▶ Creating S3 state bucket..."
if [ "${AWS_REGION}" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  Bucket already exists, skipping."
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>/dev/null || echo "  Bucket already exists, skipping."
fi

# Versioning
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

# Encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration "{
    \"Rules\": [{
      \"ApplyServerSideEncryptionByDefault\": {
        \"SSEAlgorithm\": \"aws:kms\",
        \"KMSMasterKeyID\": \"${KMS_KEY_ID}\"
      },
      \"BucketKeyEnabled\": true
    }]
  }"

# Block all public access
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Lifecycle: expire old state versions after 90 days
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET_NAME}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-versions",
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90},
      "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7}
    }]
  }'

echo "  ✓ S3 bucket: ${BUCKET_NAME}"

# ─────────────────────────────────────────────
# DynamoDB table for state locking
# ─────────────────────────────────────────────
echo "▶ Creating DynamoDB lock table..."
aws dynamodb create-table \
  --table-name "${DYNAMO_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${AWS_REGION}" \
  --sse-specification Enabled=true,SSEType=KMS,KMSMasterKeyId="${KMS_KEY_ID}" \
  2>/dev/null || echo "  DynamoDB table already exists, skipping."

echo "  ✓ DynamoDB table: ${DYNAMO_TABLE}"

# ─────────────────────────────────────────────
# Update backend config in main.tf
# ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Bootstrap complete!                        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Update terraform/main.tf backend block with:"
echo ""
echo "    backend \"s3\" {"
echo "      bucket         = \"${BUCKET_NAME}\""
echo "      key            = \"${ENVIRONMENT}/terraform.tfstate\""
echo "      region         = \"${AWS_REGION}\""
echo "      encrypt        = true"
echo "      kms_key_id     = \"${KMS_KEY_ID}\""
echo "      dynamodb_table = \"${DYNAMO_TABLE}\""
echo "    }"
echo ""
echo "  Then run:"
echo "    cd terraform && terraform init \\"
echo "      -backend-config=\"bucket=${BUCKET_NAME}\" \\"
echo "      -backend-config=\"dynamodb_table=${DYNAMO_TABLE}\""
