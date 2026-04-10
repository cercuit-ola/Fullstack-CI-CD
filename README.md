# Secure CI/CD Pipeline on AWS

A production-grade, security-gated CI/CD pipeline with **zero long-lived AWS credentials** and **four automated security gates** that must all pass before any code reaches production.
By Samuel Okediji

```
 Developer Push
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                           │
│                                                             │
│  Gate 1          Gate 2          Gate 3          Gate 4    │
│  ┌────────┐    ┌─────────┐    ┌──────────────┐  ┌───────┐  │
│  │ OWASP  │───▶│Checkov  │───▶│ Gitleaks     │  │ ECS   │  │
│  │ Dep    │    │ IaC     │    │ +            │─▶│Deploy │  │
│  │ Check  │    │ Scan    │    │ Trivy        │  │       │  │
│  └────────┘    └─────────┘    └──────────────┘  └───────┘  │
│  (parallel)    (parallel)      (parallel)       (sequential)│
└─────────────────────────────────────────────────────────────┘
      │                                                 │
      │ OIDC — no long-lived keys                       ▼
      └──────────────────────────────────────▶  Amazon ECS (Fargate)
```

## Security Gates

| Gate | Tool | What it checks | Fail condition |
|------|------|----------------|----------------|
| 1 | **OWASP Dependency-Check** | Known CVEs in app dependencies | CVSS ≥ 7 |
| 2 | **Checkov** | Terraform IaC misconfigurations | HIGH / CRITICAL findings |
| 3a | **Gitleaks** | Secrets/credentials in code & git history | Any secret detected |
| 3b | **Trivy** | Container image + filesystem CVEs | CRITICAL / HIGH (unfixed) |
| 4 | **ECS Deploy** | Build, push to ECR, deploy to Fargate | Any previous gate failing |

Gates 1–3 run in **parallel**. Gate 4 only runs if all three pass and the push is to `main`.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                      AWS                            │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │                    VPC                      │   │
│  │  ┌──────────────┐    ┌──────────────────┐   │   │
│  │  │ Public Subnet│    │  Private Subnet  │   │   │
│  │  │    (ALB)     │───▶│   (ECS Fargate)  │   │   │
│  │  └──────────────┘    └────────┬─────────┘   │   │
│  └────────────────────────────── │ ────────────┘   │
│                                  │ (via NAT GW)     │
│  ┌────────────────┐  ┌───────────▼──────────────┐   │
│  │      ECR       │  │     Secrets Manager      │   │
│  │  (KMS-encrypted│  │  (KMS-encrypted, no      │   │
│  │   immutable    │  │   long-lived creds)       │   │
│  │    tags)       │  └──────────────────────────┘   │
│  └────────────────┘                                 │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │              IAM (OIDC)                      │   │
│  │  GitHub Actions assumes role via OIDC token  │   │
│  │  — no IAM access keys ever created           │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Zero Long-Lived Credentials

GitHub Actions authenticates to AWS using **OIDC** (OpenID Connect):

1. GitHub generates a short-lived OIDC token for each workflow run
2. The token is exchanged for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`
3. Credentials expire when the job ends — nothing to rotate, nothing to leak

No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` is ever created or stored.

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── pipeline.yml          # 4-gate CI/CD pipeline
├── terraform/
│   ├── main.tf                   # Root module
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   │   ├── ecs/                  # Fargate cluster, ALB, service
│   │   ├── ecr/                  # Container registry
│   │   ├── iam/                  # OIDC role + ECS roles
│   │   ├── secrets/              # Secrets Manager + KMS
│   │   └── vpc/                  # VPC, subnets, NAT, flow logs
│   └── environments/
│       ├── prod/terraform.tfvars
│       └── dev/terraform.tfvars
├── app/
│   ├── Dockerfile                # Multi-stage, non-root, minimal
│   ├── requirements.txt
│   ├── src/main.py               # FastAPI app
│   └── tests/test_main.py
├── scripts/
│   └── bootstrap.sh              # One-time state backend setup
├── .checkov.yaml                 # Checkov IaC scanner config
├── .gitleaks.toml                # Gitleaks secret scanner config
├── .owasp-suppressions.xml       # OWASP false-positive suppressions
├── .trivyignore                  # Trivy accepted-risk entries
├── .pre-commit-config.yaml       # Local pre-commit hooks
└── trivy.yaml                    # Trivy scanner config
```

## Setup

### 1. Bootstrap Terraform State Backend

```bash
chmod +x scripts/bootstrap.sh
AWS_PROFILE=admin ./scripts/bootstrap.sh prod
```

This creates:
- S3 bucket with versioning, KMS encryption, and blocked public access
- DynamoDB table for state locking
- KMS key with automatic rotation enabled

### 2. Provision Infrastructure

```bash
cd terraform
terraform init -backend-config="bucket=<output from bootstrap>"
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

### 3. Configure GitHub Secrets

After `terraform apply`, set these in your GitHub repo secrets:

| Secret | Value | How to get it |
|--------|-------|---------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN | `terraform output github_actions_role_arn` |

That's it. No AWS access keys needed.

### 4. Install Pre-commit Hooks (local development)

```bash
pip install pre-commit
pre-commit install
```

Gitleaks and Checkov will now run on every local commit before it reaches the pipeline.

## Security Design Decisions

**Immutable ECR tags** — Once an image SHA is pushed, it cannot be overwritten. Prevents supply-chain attacks via tag mutation.

**Read-only container filesystem** — The ECS task definition sets `readonlyRootFilesystem: true`. Only `/tmp` is writable.

**Non-root container user** — The Dockerfile creates and switches to UID 1000. The container has no root privileges.

**Secrets never in environment variables (at build time)** — All secrets are pulled from Secrets Manager at ECS task startup via the `secrets` field in the task definition, not baked into images or passed as plaintext env vars.

**VPC Flow Logs** — All VPC traffic is logged to CloudWatch for audit and incident response.

**ALB access logs** — All HTTP requests logged to an encrypted, versioned S3 bucket.

**Deployment circuit breaker** — ECS will automatically roll back a failed deployment rather than leaving the service degraded.

**OWASP suppressions require expiry** — The suppression file template enforces a 90-day maximum expiry on all false-positive suppressions, preventing them from becoming permanent technical debt.

## Adding a New Secret

```bash
# Store the secret
aws secretsmanager create-secret \
  --name "prod/secure-app/my-new-secret" \
  --secret-string "actual-value-here"

# Reference it in terraform/variables.tf app_secrets map,
# then re-apply — ECS will receive it as an env var at runtime.
```

## Extending the Pipeline

To add a new security gate, add a new job to `.github/workflows/pipeline.yml` and add it to the `needs:` list on the `deploy` job:

```yaml
deploy:
  needs: [gate-owasp, gate-checkov, gate-gitleaks, gate-trivy, gate-your-new-check]
```

The deploy gate will not run unless every listed gate passes.
# Fullstack-CI-CD
