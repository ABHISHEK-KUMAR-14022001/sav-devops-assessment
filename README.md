# Secure Web Service on AWS — Terraform

This repository contains my solution for the Sav DevOps practical assessment. It uses Terraform to deploy a simple Nginx website on Amazon ECS Fargate and makes it accessible through an internet-facing Application Load Balancer (ALB).

I have configured the AWS monthly budget with actual-cost alerts at $1, $3, and $5. I have attached a screenshot of the budget configuration for reference.

The AWS account already has approximately $0.70 in actual costs, with a forecasted monthly cost of around $1.07. I wanted to mention this before deploying the assessment resources.

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

The website can be accessed using the ALB URL. The ECS tasks have public IP addresses so they can download the Nginx image from the internet. However, users cannot access the tasks directly because the security group only allows traffic from the ALB.

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

![ecs service](/public/images/ecs-service.png)

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

![target group](/public/images/target-group.png)

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

![subnets/AZs](/public/images/zones-enis.png)

## 7. Required proof evidence

Created a folder named evidence/ and saved the command outputs in it.

### Proof 1 — ALB returns HTTP 200

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -sS -D - -o /dev/null "http://${ALB_DNS}/" \
  | tee evidence/alb-curl.txt
```


![ALB returns HTTP 200](/public/images/image-alb-dns-response.png)


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

![security group](/public/images/image-sg.png)

### Proof 3 — Direct task public IP fails

the task ENIs and public IPs in the AWS CLI. Run the test from a machine outside the VPC, replacing the placeholder with an actual task public IP:

```bash
curl --connect-timeout 5 --max-time 8 -v \
  "http://TASK_PUBLIC_IP/" \
  > evidence/task-1-direct-access-test.txt 2>&1
```

![public IP](/public/images/public-ip.png)

```text
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed

  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0*   Trying 13.233.140.171:80...

  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  0     0    0     0    0     0      0      0 --:--:--  0:00:02 --:--:--     0
  0     0    0     0    0     0      0      0 --:--:--  0:00:03 --:--:--     0
  0     0    0     0    0     0      0      0 --:--:--  0:00:04 --:--:--     0* ipv4 connect timeout after 5000ms, move on!
* Failed to connect to 13.233.140.171 port 80 after 5001 ms: Timeout was reached

  0     0    0     0    0     0      0      0 --:--:--  0:00:05 --:--:--     0
* Closing connection
curl: (28) Failed to connect to 13.233.140.171 port 80 after 5001 ms: Timeout was reached
curl exit code: 28
```

## 8. Screenshots

Saveed relevant AWS Console screenshots under `screenshots/`:

- AWS VPC showing CIDR 10.20.0.0/16
- Both subnets with their different Availability Zones
- ALB security group inbound rule
- Task security group inbound rule referencing the ALB security group
- ECS service with two running tasks
- Target group with both targets healthy
- Nginx welcome page opened through the ALB DNS name
- CloudWatch log group/log streams


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


