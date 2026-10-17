# Secure Web Service on AWS — Terraform

This repository implements the Sav DevOps practical assessment. It provisions a small Nginx website on Amazon ECS Fargate behind an internet-facing Application Load Balancer (ALB).

> **Cost warning:** Create a USD 5 AWS Budget alert before deployment. A budget alert does not stop spending. The ALB, Fargate tasks, public IPv4 addresses, and related usage can incur charges. Save all evidence and destroy the stack on the same day. The assessment's approximately USD 1 target is an estimate, not a guaranteed maximum.

## 1. Architecture

```text
Internet
   |
   | HTTP :80
   v
Application Load Balancer (public, two AZs)
   |  ALB security group: TCP/80 from 0.0.0.0/0
   v
Target group (IP targets, HTTP health check /)
   |
   +-------------------------------+
   |                               |
   v                               v
ECS Fargate task 1              ECS Fargate task 2
Public subnet 1 / AZ A          Public subnet 2 / AZ B
Nginx container :80             Nginx container :80
Task SG: inbound TCP/80 only from ALB SG
```

The site URL is the ALB DNS name. Although the tasks have public IPv4 addresses so they can pull the public Nginx image through the internet gateway, the task security group does not allow direct inbound HTTP from the internet.

## 2. Resources and required settings

- AWS region: `ap-south-1` (Mumbai)
- VPC CIDR: `10.20.0.0/16`
- Public subnet CIDRs: `10.20.1.0/24` and `10.20.2.0/24`, in two different Availability Zones
- Internet gateway and `0.0.0.0/0` routes for both public subnets
- ALB security group: inbound TCP/80 from `0.0.0.0/0`
- Task security group: inbound TCP/80 only from the ALB security group
- ECS launch type: Fargate
- Task size: `256` CPU units (0.25 vCPU), `512` MiB memory
- Desired task count: 2
- Image: `public.ecr.aws/docker/library/nginx:stable-alpine`
- Container port: 80
- Logs: `awslogs` to CloudWatch Logs
- ALB target type: IP, health check path `/`, expected HTTP status `200`

## 3. Files

- `main.tf` — VPC, networking, security groups, IAM execution role, CloudWatch log group, ECS, ALB, target group, and listener
- `variables.tf` — region, name prefix, and container image
- `versions.tf` — Terraform and AWS provider constraints
- `outputs.tf` — ALB URL and relevant resource IDs
- `.terraform.lock.hcl` — provider dependency lock file; commit it to Git

## 4. Prerequisites

1. An AWS account with permission to create and delete the resources in this configuration.
2. AWS CLI and Terraform 1.5 or newer.
3. Credentials configured using an authorized IAM identity. Avoid root access keys and do not commit credentials.
4. A USD 5 budget alert created in AWS Billing before applying.

Confirm identity and region:

```bash
aws sts get-caller-identity
aws configure get region
```

The region should be `ap-south-1`. The Terraform AWS provider also sets this region from `variables.tf`.

## 5. Deploy

Run from the directory containing the `.tf` files:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=assessment.tfplan
terraform apply assessment.tfplan
```

Review the plan before applying it. If this directory manages an existing stack, inspect any proposed changes or deletions carefully.

Get the site URL:

```bash
terraform output -raw website_url
```

## 6. Verify the deployment

### ECS service

```bash
aws ecs describe-services \
  --cluster sav-web-assessment-cluster \
  --services sav-web-assessment-service \
  --region ap-south-1 \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}'
```

Expected: desired count `2`, running count `2`, pending count `0`.

### Target group health

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names sav-web-assessment-tg \
  --region ap-south-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region ap-south-1 \
  --query 'TargetHealthDescriptions[].{IP:Target.Id,Port:Target.Port,Health:TargetHealth.State}'
```

Both targets should be `healthy`.

### Confirm task placement

Verify the running tasks' Availability Zones and ENIs, and confirm that they are in separate subnets/AZs. The service uses both subnets and a spread placement strategy, but record the actual placement from AWS rather than assuming it.

```bash
TASK_ARNS=$(aws ecs list-tasks \
  --cluster sav-web-assessment-cluster \
  --service-name sav-web-assessment-service \
  --region ap-south-1 \
  --query 'taskArns' --output text)

aws ecs describe-tasks \
  --cluster sav-web-assessment-cluster \
  --tasks $TASK_ARNS \
  --region ap-south-1 \
  --query 'tasks[].{Task:taskArn,AZ:availabilityZone,Status:lastStatus,ENI:attachments[0].details[?name==`networkInterfaceId`].value|[0]}'
```

## 7. Required proof evidence

Create an `evidence/` directory and save the actual command output. Do not leave the placeholders below in the submitted README.

### Proof 1 — ALB returns HTTP 200

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -sS -D - -o /dev/null "http://${ALB_DNS}/" \
  | tee evidence/alb-curl.txt
```

Expected: an HTTP `200 OK` response. Paste the actual output here:

```text
[PASTE ACTUAL HTTP RESPONSE HEADERS]
```

### Proof 2 — Task SG only allows HTTP from the ALB SG

```bash
TASK_SG=$(terraform output -raw task_security_group_id)

aws ec2 describe-security-groups \
  --group-ids "$TASK_SG" \
  --region ap-south-1 \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json \
  | tee evidence/task-security-group.json
```

Verify that TCP/80 references the ALB security group and that there is no public inbound rule on the task security group.

```text
[PASTE OR SUMMARIZE THE ACTUAL RULE OUTPUT]
```

### Proof 3 — Direct task public IP fails

Find the task ENIs and public IPs in the ECS/EC2 console or with the AWS CLI. Run the test from a machine outside the VPC, replacing the placeholder with an actual task public IP:

```bash
curl --connect-timeout 5 --max-time 8 -v \
  "http://TASK_PUBLIC_IP/" \
  > evidence/direct-task-curl.txt 2>&1
```

Expected: a timeout or connection refused because the task security group does not allow inbound HTTP from the test machine. Paste the actual output here:

```text
[PASTE ACTUAL CURL OUTPUT AND EXIT CODE]
```

Do not claim a test passed unless you ran it and captured the result.

## 8. Screenshots

Save relevant AWS Console screenshots under `screenshots/`:

- VPC and both subnets with CIDRs and AZs
- ALB security group inbound rule
- Task security group inbound rule referencing the ALB security group
- ECS service with two running tasks
- Target group with both targets healthy
- Nginx welcome page opened through the ALB DNS name
- CloudWatch log group/log streams

Do not include credentials, access keys, or other secrets in screenshots.

## 9. Design notes

### 1. Follow one successful request

The browser sends HTTP to the ALB DNS name on port 80. The ALB security group allows the incoming request. The ALB listener forwards it to the IP target group. The target group chooses a healthy Fargate task. The task security group allows port 80 from the ALB security group, and Nginx responds. The response returns through the ALB to the browser.

### 2. Why the task public IP is not directly accessible

A public IP provides a route, but it does not automatically permit inbound connections. The task security group allows inbound TCP/80 only when the source is the ALB security group. Direct HTTP from an external client is therefore blocked by the task security group.

### 3. How the task pulls the Nginx image

The task ENI has a public IPv4 address in a subnet whose default route points to the internet gateway. The task initiates an outbound connection to public ECR to pull the image. Security groups are stateful, so response traffic for permitted outbound connections is allowed.

If tasks have only private IP addresses, provide an outbound path such as a NAT gateway with suitable private-subnet routes. For ECR-hosted images, suitable ECR API and Docker registry interface endpoints plus an S3 gateway endpoint can avoid general internet egress. A public registry such as the specified public ECR image may require a suitable NAT or other egress path when tasks have only private IPs.

### 4. What happens if one Availability Zone fails?

The ALB spans two Availability Zones and can route to healthy targets in the surviving zone. ECS may replace failed tasks, but available capacity can temporarily drop to one task. This is not a guarantee of uninterrupted service. The design does not protect against a regional outage, account-wide issues, application defects, compromised credentials, or every infrastructure failure.

### 5. Production improvements

- **HTTPS:** Add a domain and ACM certificate, configure an HTTPS listener on port 443, and redirect HTTP to HTTPS.
- **Logging:** Configure ALB access logs to a protected S3 bucket, choose appropriate CloudWatch retention, and create alarms for errors and unhealthy targets.
- **Autoscaling:** Configure ECS Service Auto Scaling using CPU or memory metrics with sensible minimum/maximum task counts and cooldowns.
- **Pipeline:** Run formatting, validation, security checks, and a Terraform plan in CI. Require review/approval before apply, use short-lived credentials (such as OIDC role assumption), store state remotely with locking, and use immutable image versions/digests with a rollback strategy.

## 10. Teardown and cost verification

After saving the required command output and screenshots, destroy the stack on the same day:

```bash
terraform destroy
```

Review the proposed deletions and confirm. Then check the AWS Console to ensure that the ECS service/tasks, ALB, target group, security groups, subnets, VPC, and other resources managed by this Terraform configuration have been removed.

Record the actual result below after teardown:

- Destroy completed: **[YES/NO — fill in after running]**
- Date/time: **[FILL IN ACTUAL DATE/TIME]**
- Remaining assessment resources: **[FILL IN AFTER VERIFICATION]**
- Actual cost observed: **[FILL IN FROM AWS BILLING WHEN AVAILABLE]**

A budget alert is not a spending cap. Verify that billable resources were removed and check billing for any remaining charges.

## 11. Repository submission

Push the Terraform files, `.terraform.lock.hcl`, README, evidence, and screenshots to a Git repository you own. Do not commit `.terraform/`, Terraform state files, plans, credentials, or secrets.

```bash
git add main.tf variables.tf versions.tf outputs.tf .terraform.lock.hcl README.md evidence/ screenshots/
git commit -m "Complete secure AWS ECS Fargate assessment"
git push
```

Submit the repository URL when the assessment deadline arrives.
