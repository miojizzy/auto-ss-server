---
name: aws-ec2-management
description: 'Manage AWS EC2 resources using AWS CLI: instances (start/stop/create/terminate/describe), launch templates (create/modify/describe), security groups (create/update/describe rules), Elastic IPs (allocate/associate/release), resource usage metrics via CloudWatch, and cost/billing estimates via AWS Cost Explorer and Budgets API. Use when asked about EC2 instances, security groups, public IPs, launch templates, AWS billing, monthly costs, or any AWS resource management task.'
---

# AWS EC2 Management

Comprehensive toolkit for managing AWS EC2 infrastructure via AWS CLI, including instances, launch templates, security groups, Elastic IPs, and cost estimation.

## When to Use This Skill

- User asks to list, start, stop, create, or terminate EC2 instances
- User asks about launch templates (create, modify, describe)
- User asks to manage security groups or inbound/outbound rules
- User asks about Elastic IPs or public IP addresses
- User asks about resource usage, CloudWatch metrics, or billing
- User wants a monthly cost estimate or spend breakdown
- Any mention of EC2, AWS instances, security groups, or AWS costs

## Prerequisites

- AWS CLI installed and configured: `aws configure` or environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`
- Sufficient IAM permissions for the operations requested
- Verify credentials: `aws sts get-caller-identity`

## EC2 Instances

See [ec2-instances.md](./references/ec2-instances.md) for complete instance management commands.

### Quick Reference

```bash
# List all instances with status
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,Type:InstanceType,Name:Tags[?Key==`Name`]|[0].Value,IP:PublicIpAddress}' \
  --output table

# Start instance
aws ec2 start-instances --instance-ids i-0123456789abcdef0

# Stop instance
aws ec2 stop-instances --instance-ids i-0123456789abcdef0

# Terminate instance
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0
```

## Launch Templates

See [launch-templates.md](./references/launch-templates.md) for complete launch template commands.

### Quick Reference

```bash
# List launch templates
aws ec2 describe-launch-templates --output table

# Create a new version of a launch template
aws ec2 create-launch-template-version \
  --launch-template-id lt-0123456789abcdef0 \
  --source-version '$Latest' \
  --launch-template-data '{"InstanceType":"t3.medium"}'

# Launch instance from template
aws ec2 run-instances \
  --launch-template LaunchTemplateId=lt-0123456789abcdef0,Version='$Latest' \
  --count 1
```

## Security Groups

See [security-groups.md](./references/security-groups.md) for complete security group commands.

### Quick Reference

```bash
# List security groups
aws ec2 describe-security-groups \
  --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName,VPC:VpcId,Desc:Description}' \
  --output table

# Add inbound rule (e.g., SSH from specific IP)
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 22 \
  --cidr 203.0.113.0/24

# Remove inbound rule
aws ec2 revoke-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 22 \
  --cidr 203.0.113.0/24
```

## Elastic IPs (Public IPs)

See [elastic-ips.md](./references/elastic-ips.md) for complete Elastic IP commands.

### Quick Reference

```bash
# List all Elastic IPs
aws ec2 describe-addresses \
  --query 'Addresses[*].{AllocationId:AllocationId,IP:PublicIp,InstanceId:InstanceId,AssociationId:AssociationId}' \
  --output table

# Allocate a new Elastic IP
aws ec2 allocate-address --domain vpc

# Associate with instance
aws ec2 associate-address \
  --instance-id i-0123456789abcdef0 \
  --allocation-id eipalloc-0123456789abcdef0

# Release Elastic IP
aws ec2 release-address --allocation-id eipalloc-0123456789abcdef0
```

## Resource Usage & Metrics (CloudWatch)

See [cloudwatch-metrics.md](./references/cloudwatch-metrics.md) for complete monitoring commands.

### Quick Reference

```bash
# Get CPU utilization for an instance (last 1 hour)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --output table

# Get network in/out
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkIn \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Sum \
  --output table
```

## Cost & Billing Estimates

See [cost-billing.md](./references/cost-billing.md) for complete cost management commands.

### Quick Reference

```bash
# Current month total cost
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --output table

# Cost breakdown by service this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output table

# EC2 instance cost breakdown by instance
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --group-by Type=TAG,Key=Name \
  --output table
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `UnauthorizedOperation` | Check IAM permissions for the specific API call |
| `InvalidInstanceID.NotFound` | Verify instance ID and region (`--region`) |
| `InvalidGroup.NotFound` | Verify security group ID and VPC |
| `AddressLimitExceeded` | Request Elastic IP limit increase via AWS Support |
| `InsufficientInstanceCapacity` | Try a different availability zone or instance type |
| Credentials error | Run `aws configure` or check env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| Wrong region | Set `AWS_DEFAULT_REGION` or pass `--region us-east-1` |

## References

- [EC2 Instance Commands](./references/ec2-instances.md)
- [Launch Template Commands](./references/launch-templates.md)
- [Security Group Commands](./references/security-groups.md)
- [Elastic IP Commands](./references/elastic-ips.md)
- [CloudWatch Metrics](./references/cloudwatch-metrics.md)
- [Cost & Billing](./references/cost-billing.md)
