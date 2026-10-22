# Deployment guide

Everything is deployed by the GitHub Actions pipeline; the only manual step is a one-time bootstrap
that creates the Terraform state bucket and the OIDC role the pipeline uses.

## 0. Prerequisites

| Need | Notes |
| --- | --- |
| AWS account + admin credentials on your laptop | Used only for the one-time bootstrap |
| Terraform >= 1.10 and AWS CLI v2 | `terraform -version`, `aws sts get-caller-identity` |
| A domain you control | Easiest: a public Route 53 hosted zone (ACM validation is then fully automated) |
| GitHub repository | Push this project to it |

You need two values from the domain: the **FQDN** the app will use (for example `app.example.com`) and the
**hosted zone ID** (Route 53 console, or `aws route53 list-hosted-zones`).

## 1. Bootstrap (once, from your laptop)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_repository = "<user>/<repo>"
terraform init
terraform apply
```

Note the two outputs:

* `state_bucket` -> GitHub repository **variable** `TF_STATE_BUCKET`
* `github_actions_role_arn` -> GitHub repository **secret** `AWS_ROLE_ARN`

If the account already has a GitHub OIDC provider, set `create_github_oidc_provider = false` first
(only one provider per account is allowed).

## 2. Configure GitHub

Repository -> Settings -> Secrets and variables -> Actions.

| Type | Name | Value |
| --- | --- | --- |
| Secret | `AWS_ROLE_ARN` | bootstrap output |
| Variable | `TF_STATE_BUCKET` | bootstrap output |
| Variable | `AWS_REGION` | `ap-south-1` |
| Variable | `DOMAIN_NAME` | `app.example.com` |
| Variable | `HOSTED_ZONE_ID` | Route 53 zone ID (leave empty if DNS is elsewhere) |
| Variable | `CERTIFICATE_ARN` | leave empty to let Terraform create the ACM certificate |

Then Settings -> Environments -> **New environment** named `production`, and add yourself as a
**required reviewer**. Every apply/destroy pauses there until approved.

## 3. Deploy

1. Create a branch, change something under `terraform/` or `app/`, open a pull request.
   The pipeline runs fmt, validate, tflint and `terraform plan`, and posts the plan as a PR comment.
2. Merge the pull request. The `apply` job waits for your approval on the `production` environment, runs
   `terraform apply`, then runs `scripts/validate-deployment.sh` against the live URL.
3. First apply takes about 20-25 minutes (Multi-AZ RDS and ACM validation dominate).

You can also run it by hand: **Actions -> Terraform CI/CD -> Run workflow -> apply**.

## 4. Verify

The pipeline already runs these checks; run them yourself for the screenshots:

```bash
bash scripts/validate-deployment.sh https://app.example.com
curl -sI http://app.example.com          # 301 -> https
curl -s  https://app.example.com/api/status | jq
```

Open `https://app.example.com` in a browser: refresh a few times and watch the instance ID and
Availability Zone change as the ALB balances requests across both AZs.

Useful console checks: EC2 -> Target Groups (2 healthy targets), Auto Scaling Groups (instances in two
AZs), RDS (Multi-AZ = Yes, Publicly accessible = No, Encrypted = Yes), S3 (ALB log objects under
`alb/AWSLogs/...`, after a few minutes), Secrets Manager (`devops-task-dev/db-credentials`).

## 5. Roll out an application change

Edit `app/app.py`, push, merge. Terraform hashes the `app/` folder, uploads a new package to S3 and
creates a new launch template version; the Auto Scaling group performs a rolling instance refresh
(at least 50% of capacity stays in service). The home page shows the new `App version`.

## 6. Tear down (stops all charges)

**Actions -> Terraform CI/CD -> Run workflow -> destroy** (approve on the `production` environment), or
locally `cd terraform && terraform destroy`. Afterwards optionally `cd bootstrap && terraform destroy`
(empty the state bucket first).

## Local run (optional)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl            # put your state bucket name in
terraform init -backend-config=backend.hcl
terraform plan
```

Commit the generated `terraform/.terraform.lock.hcl` so provider versions stay pinned.

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| Apply stuck on `aws_acm_certificate_validation` | `HOSTED_ZONE_ID` does not match the domain, or the domain's registrar is not delegating to that hosted zone's name servers |
| Targets stay `unhealthy` | Instances still booting (allow ~5 min). Check `/var/log/user-data.log` through EC2 -> Connect -> Session Manager; verify NAT gateway exists and routes are associated |
| `/db-health` returns 503 | Check security groups (db-sg must allow 3306 from app-sg), then `journalctl -u webapp` on an instance |
| ALB access-log error: "Access Denied for bucket" | Region launched after Aug 2022: the bucket policy already contains the log-delivery service principal; for the legacy account principal the data source must support your region |
| `Secret ... scheduled for deletion` on re-create | Raise/lower `secret_recovery_window_days`; default `0` deletes immediately on destroy |
| `EntityAlreadyExists` for OIDC provider (bootstrap) | Set `create_github_oidc_provider = false` |
| Pipeline cannot assume the role | The role trust is limited to `main`, `environment:production` and `pull_request` of the repository named in `github_repository` |
