# Screenshot checklist

Capture these after a successful deployment and save them in this folder using the suggested names.
Hide account IDs if you plan to share the repository publicly.

| # | File name | What to show |
| --- | --- | --- |
| 1 | `01-github-actions-pipeline.png` | Successful run of **Terraform CI/CD** with all jobs green (validate, plan, apply) |
| 2 | `02-pr-plan-comment.png` | The terraform plan comment on a pull request |
| 3 | `03-validation-output.png` | Log of the "End-to-end validation" step showing all checks PASS |
| 4 | `04-app-https-browser.png` | Application open at the https URL, padlock visible, instance/AZ/DB status shown |
| 5 | `05-http-redirect.png` | `curl -sI http://<domain>` showing `301` to https |
| 6 | `06-vpc-resource-map.png` | VPC -> Resource map (public, private app, private db subnets in two AZs, IGW, NAT) |
| 7 | `07-alb-listeners.png` | ALB -> Listeners: 80 redirect, 443 with the ACM certificate and TLS 1.3 policy |
| 8 | `08-target-group-healthy.png` | Target group with healthy targets in two AZs |
| 9 | `09-asg-instances.png` | Auto Scaling group: launch template, min/max/desired, instances in both AZs |
| 10 | `10-rds-config.png` | RDS: Multi-AZ, Encryption enabled, Publicly accessible = No, private subnet group |
| 11 | `11-security-groups.png` | Inbound rules of alb-sg, app-sg (source = alb-sg) and db-sg (source = app-sg) |
| 12 | `12-secrets-manager.png` | Secret `devops-task-dev/db-credentials` (do NOT reveal the value) |
| 13 | `13-s3-buckets.png` | App bucket (encryption, versioning, block public access) and ALB log objects |
| 14 | `14-iam-role-policy.png` | EC2 instance role with the scoped inline policy |
| 15 | `15-terraform-state.png` | S3 state bucket with the `terraform.tfstate` object (and versioning on) |
