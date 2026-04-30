# AWS Cost & Billing Management

Complete AWS CLI reference for monitoring costs and estimating monthly spend.

**Prerequisites:** Enable Cost Explorer in the AWS Console (Billing > Cost Explorer). It may take 24 hours for data to appear.

## Current Month Total Cost

```bash
# Total cost this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[0].Total.UnblendedCost.{Amount:Amount,Unit:Unit}'

# Cost by day this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[*].{Date:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}' \
  --output table
```

## Cost Breakdown by Service

```bash
# Cost by service this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Keys[0]!=`Tax`].{Service:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table

# Sort by highest cost (requires jq)
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE | \
  jq -r '.ResultsByTime[0].Groups | sort_by(.Metrics.UnblendedCost.Amount | tonumber) | reverse | .[] | [.Keys[0], .Metrics.UnblendedCost.Amount] | @tsv'
```

## EC2-Specific Cost Breakdown

```bash
# EC2 compute cost this month
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[0].Total.UnblendedCost'

# EC2 cost by instance type
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
  --query 'ResultsByTime[0].Groups[*].{Type:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table

# EC2 cost by Name tag
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --group-by Type=TAG,Key=Name \
  --query 'ResultsByTime[0].Groups[*].{Name:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table

# EC2 cost by region
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --group-by Type=DIMENSION,Key=REGION \
  --query 'ResultsByTime[0].Groups[*].{Region:Keys[0],Cost:Metrics.UnblendedCost.Amount}' \
  --output table
```

## Monthly Spend Forecast

```bash
# Forecast for rest of month
LAST_DAY=$(python3 -c "import calendar,datetime; t=datetime.date.today(); print(calendar.monthrange(t.year,t.month)[1])")
aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-%d),End=$(date +%Y-%m-$LAST_DAY) \
  --metric UNBLENDED_COST \
  --granularity MONTHLY \
  --query '{ForecastedAmount:Total.Amount,Unit:Total.Unit,LowerBound:ForecastResultsByTime[0].PredictionIntervalLowerBound,UpperBound:ForecastResultsByTime[0].PredictionIntervalUpperBound}'

# 3-month forecast
aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-%d),End=$(date -d '+3 months' +%Y-%m-01 2>/dev/null || date -v+3m +%Y-%m-01) \
  --metric UNBLENDED_COST \
  --granularity MONTHLY \
  --query 'ForecastResultsByTime[*].{Period:TimePeriod.Start,Mean:MeanValue,Low:PredictionIntervalLowerBound,High:PredictionIntervalUpperBound}' \
  --output table
```

## Historical Cost Analysis

```bash
# Last 6 months by service
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '-6 months' +%Y-%m-01 2>/dev/null || date -v-6m +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
services = {}
for month in data['ResultsByTime']:
    period = month['TimePeriod']['Start'][:7]
    for group in month['Groups']:
        svc = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        if cost > 0.01:
            services.setdefault(svc, {})[period] = cost
for svc, months in sorted(services.items(), key=lambda x: sum(x[1].values()), reverse=True)[:10]:
    total = sum(months.values())
    print(f'{total:8.2f} USD  {svc}')
"

# Year-to-date cost
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-01-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[*].{Month:TimePeriod.Start,Cost:Total.UnblendedCost.Amount}' \
  --output table
```

## AWS Budgets

```bash
# List budgets
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query 'Account' --output text)

# Create a monthly budget with alert at 80%
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
aws budgets create-budget \
  --account-id $ACCOUNT_ID \
  --budget '{
    "BudgetName": "MonthlyEC2Budget",
    "BudgetLimit": {"Amount": "100", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "Service": ["Amazon Elastic Compute Cloud - Compute"]
    }
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "you@example.com"
    }]
  }]'

# Create a total monthly budget
aws budgets create-budget \
  --account-id $ACCOUNT_ID \
  --budget '{
    "BudgetName": "TotalMonthlyBudget",
    "BudgetLimit": {"Amount": "200", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 100,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "you@example.com"
    }]
  }]'
```

## Cost Optimization Tips

```bash
# Find stopped instances (still billed for EBS storage)
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,Stopped:StateTransitionReason}' \
  --output table

# Find unattached EBS volumes (still billed, ~$0.10/GB/month for gp3)
aws ec2 describe-volumes \
  --filters "Name=status,Values=available" \
  --query 'Volumes[*].{ID:VolumeId,Size:Size,Type:VolumeType,Created:CreateTime}' \
  --output table

# Find unassociated Elastic IPs (billed at ~$0.005/hour when not attached)
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].{AllocationId:AllocationId,IP:PublicIp}' \
  --output table

# Find old/unused EBS snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --query 'sort_by(Snapshots, &StartTime)[*].{ID:SnapshotId,Size:VolumeSize,Date:StartTime,Desc:Description}' \
  --output table
```
