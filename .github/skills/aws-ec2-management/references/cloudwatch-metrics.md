# CloudWatch Metrics & Resource Usage

Complete AWS CLI reference for monitoring EC2 resource usage via CloudWatch.

## Available EC2 Metrics

| Metric | Description | Unit |
|--------|-------------|------|
| `CPUUtilization` | Percentage of CPU used | Percent |
| `NetworkIn` | Bytes received | Bytes |
| `NetworkOut` | Bytes sent | Bytes |
| `NetworkPacketsIn` | Packets received | Count |
| `NetworkPacketsOut` | Packets sent | Count |
| `DiskReadBytes` | Bytes read from disk | Bytes |
| `DiskWriteBytes` | Bytes written to disk | Bytes |
| `DiskReadOps` | Read IOPS | Count |
| `DiskWriteOps` | Write IOPS | Count |
| `StatusCheckFailed` | Both status checks failed | Count |
| `StatusCheckFailed_Instance` | Instance status check failed | Count |
| `StatusCheckFailed_System` | System status check failed | Count |

*Note: Memory, disk usage %, and other OS-level metrics require CloudWatch Agent.*

## Getting Metrics

```bash
# CPU utilization - last hour average
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average Maximum \
  --query 'sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,Avg:Average,Max:Maximum}' \
  --output table

# Network usage - last 24 hours
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkIn \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Sum \
  --output table

# Status check failed - last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name StatusCheckFailed \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --output table
```

## Listing Available Metrics

```bash
# List all metrics for an instance
aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0

# List all EC2 namespaces
aws cloudwatch list-metrics --namespace AWS/EC2 \
  --query 'Metrics[*].MetricName' \
  --output text | tr '\t' '\n' | sort -u
```

## CloudWatch Alarms

```bash
# List all alarms
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Metric:MetricName}' \
  --output table

# Create CPU high alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "CPU-High-i-0123456789abcdef0" \
  --alarm-description "CPU above 80% for 5 minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:my-topic

# Create status check failed alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "StatusCheck-i-0123456789abcdef0" \
  --metric-name StatusCheckFailed \
  --namespace AWS/EC2 \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:my-topic

# Delete alarm
aws cloudwatch delete-alarms --alarm-names "CPU-High-i-0123456789abcdef0"
```

## CloudWatch Agent (OS-Level Metrics)

To collect memory usage, disk usage %, and custom metrics, install the CloudWatch Agent:

```bash
# On Amazon Linux 2 / AL2023
sudo yum install amazon-cloudwatch-agent -y

# On Ubuntu
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb

# Generate config with wizard
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard

# Start agent with config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

After installing the agent, memory metrics appear in namespace `CWAgent`:
```bash
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=i-0123456789abcdef0 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --output table
```

## EC2 Instance Usage Report

```bash
# Get running instance count by type
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceType' \
  --output text | tr '\t' '\n' | sort | uniq -c | sort -rn

# Get total running instance count
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'length(Reservations[*].Instances[])' \
  --output text

# Get instances by region (requires iterating regions)
for region in $(aws ec2 describe-regions --query 'Regions[*].RegionName' --output text); do
  count=$(aws ec2 describe-instances \
    --region $region \
    --filters "Name=instance-state-name,Values=running" \
    --query 'length(Reservations[*].Instances[])' \
    --output text 2>/dev/null)
  if [ "$count" -gt 0 ] 2>/dev/null; then
    echo "$region: $count running instances"
  fi
done
```
