# Security Group Management

Complete AWS CLI reference for EC2 security groups.

## Listing & Describing Security Groups

```bash
# List all security groups
aws ec2 describe-security-groups \
  --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName,VPC:VpcId,Description:Description}' \
  --output table

# Get security group with full rules
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0

# Filter by name
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=my-sg-*"

# Show inbound rules for a specific group
aws ec2 describe-security-groups \
  --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissions'

# Show outbound rules
aws ec2 describe-security-groups \
  --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# Find security groups used by an instance
aws ec2 describe-instances \
  --instance-ids i-0123456789abcdef0 \
  --query 'Reservations[0].Instances[0].SecurityGroups'
```

## Creating Security Groups

```bash
# Create a security group in a VPC
aws ec2 create-security-group \
  --group-name my-web-sg \
  --description "Security group for web servers" \
  --vpc-id vpc-0123456789abcdef0

# Save the group ID
SG_ID=$(aws ec2 create-security-group \
  --group-name my-web-sg \
  --description "Security group for web servers" \
  --vpc-id vpc-0123456789abcdef0 \
  --query 'GroupId' \
  --output text)
echo "Created: $SG_ID"
```

## Adding Inbound Rules

```bash
# Allow SSH from specific IP
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 22 \
  --cidr 203.0.113.0/24

# Allow HTTP from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 80 \
  --cidr 0.0.0.0/0

# Allow HTTPS from anywhere (IPv4 + IPv6)
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}],"Ipv6Ranges":[{"CidrIpv6":"::/0"}]}
  ]'

# Allow a port range
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 8000-9000 \
  --cidr 10.0.0.0/8

# Allow all traffic from another security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --ip-permissions '[
    {"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"sg-0fedcba9876543210"}]}
  ]'

# Allow all ICMP (ping)
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol icmp \
  --port -1 \
  --cidr 0.0.0.0/0

# Add rule with description
aws ec2 authorize-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"203.0.113.0/24","Description":"Office IP"}]}
  ]'
```

## Removing Inbound Rules

```bash
# Remove SSH rule
aws ec2 revoke-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 22 \
  --cidr 203.0.113.0/24

# Remove rule by specifying full ip-permissions (for complex rules)
aws ec2 revoke-security-group-ingress \
  --group-id sg-0123456789abcdef0 \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}
  ]'
```

## Adding Outbound Rules

```bash
# Allow all outbound (default)
aws ec2 authorize-security-group-egress \
  --group-id sg-0123456789abcdef0 \
  --protocol -1 \
  --cidr 0.0.0.0/0

# Allow specific outbound port
aws ec2 authorize-security-group-egress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp --port 443 \
  --cidr 0.0.0.0/0

# Remove all outbound traffic (lock down egress)
# First get the current egress rules, then revoke them
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissionsEgress'
# Then revoke each rule explicitly
```

## Modifying Security Group Rules

```bash
# Update rule description (modify-security-group-rules)
# First get the rule ID
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=sg-0123456789abcdef0" \
  --query 'SecurityGroupRules[*].{ID:SecurityGroupRuleId,Port:ToPort,CIDR:CidrIpv4,Desc:Description}' \
  --output table

# Update description of a rule
aws ec2 modify-security-group-rules \
  --group-id sg-0123456789abcdef0 \
  --security-group-rules '[{
    "SecurityGroupRuleId": "sgr-0123456789abcdef0",
    "SecurityGroupRule": {
      "Description": "Updated description",
      "IpProtocol": "tcp",
      "FromPort": 22,
      "ToPort": 22,
      "CidrIpv4": "203.0.113.0/24"
    }
  }]'
```

## Deleting Security Groups

```bash
# Delete a security group (cannot delete if in use by instances)
aws ec2 delete-security-group --group-id sg-0123456789abcdef0

# Check if group is in use before deleting
aws ec2 describe-instances \
  --filters "Name=instance.group-id,Values=sg-0123456789abcdef0" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text
```

## Common Patterns

```bash
# Create web server security group (HTTP + HTTPS + SSH)
SG_ID=$(aws ec2 create-security-group \
  --group-name web-server-sg \
  --description "Web server: HTTP, HTTPS, SSH" \
  --vpc-id vpc-0123456789abcdef0 \
  --query 'GroupId' --output text)

# Add rules
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
echo "Security group $SG_ID created with web rules"
```
