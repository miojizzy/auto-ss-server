# EC2 Instance Management

Complete AWS CLI reference for EC2 instance lifecycle management.

## Listing & Describing Instances

```bash
# List all instances with key details
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].{
    ID:InstanceId,
    State:State.Name,
    Type:InstanceType,
    Name:Tags[?Key==`Name`]|[0].Value,
    PublicIP:PublicIpAddress,
    PrivateIP:PrivateIpAddress,
    AZ:Placement.AvailabilityZone,
    LaunchTime:LaunchTime
  }' \
  --output table

# Filter by state (running, stopped, terminated)
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,IP:PublicIpAddress}' \
  --output table

# Filter by tag name
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=my-server-*" \
  --output table

# Get details of specific instance
aws ec2 describe-instances --instance-ids i-0123456789abcdef0

# Get instance status checks
aws ec2 describe-instance-status --instance-ids i-0123456789abcdef0
```

## Starting & Stopping Instances

```bash
# Start a stopped instance
aws ec2 start-instances --instance-ids i-0123456789abcdef0

# Start multiple instances
aws ec2 start-instances --instance-ids i-0123456789abcdef0 i-0fedcba9876543210

# Stop a running instance
aws ec2 stop-instances --instance-ids i-0123456789abcdef0

# Stop with hibernation
aws ec2 stop-instances --instance-ids i-0123456789abcdef0 --hibernate

# Reboot instance
aws ec2 reboot-instances --instance-ids i-0123456789abcdef0

# Wait until instance is running
aws ec2 wait instance-running --instance-ids i-0123456789abcdef0
echo "Instance is now running"

# Wait until instance is stopped
aws ec2 wait instance-stopped --instance-ids i-0123456789abcdef0
```

## Creating Instances

```bash
# Launch instance with minimum parameters
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --key-name my-key-pair \
  --security-group-ids sg-0123456789abcdef0 \
  --subnet-id subnet-0123456789abcdef0 \
  --count 1

# Launch with Name tag and user data
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --key-name my-key-pair \
  --security-group-ids sg-0123456789abcdef0 \
  --subnet-id subnet-0123456789abcdef0 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-server}]' \
  --user-data file://user-data.sh \
  --count 1

# Launch from launch template
aws ec2 run-instances \
  --launch-template LaunchTemplateId=lt-0123456789abcdef0,Version='$Latest' \
  --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-server}]'

# Launch with EBS volume
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --count 1
```

## Terminating Instances

```bash
# Terminate instance (IRREVERSIBLE)
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0

# Terminate multiple instances
aws ec2 terminate-instances --instance-ids i-0123456789abcdef0 i-0fedcba9876543210

# Enable termination protection
aws ec2 modify-instance-attribute \
  --instance-id i-0123456789abcdef0 \
  --disable-api-termination

# Remove termination protection
aws ec2 modify-instance-attribute \
  --instance-id i-0123456789abcdef0 \
  --no-disable-api-termination
```

## Modifying Instances

```bash
# Change instance type (instance must be stopped)
aws ec2 modify-instance-attribute \
  --instance-id i-0123456789abcdef0 \
  --instance-type '{"Value":"t3.medium"}'

# Add/change security groups
aws ec2 modify-instance-attribute \
  --instance-id i-0123456789abcdef0 \
  --groups sg-0123456789abcdef0 sg-0fedcba9876543210

# Update tags
aws ec2 create-tags \
  --resources i-0123456789abcdef0 \
  --tags Key=Name,Value=new-name Key=Environment,Value=production

# Remove tags
aws ec2 delete-tags \
  --resources i-0123456789abcdef0 \
  --tags Key=OldTag
```

## Key Pairs

```bash
# List key pairs
aws ec2 describe-key-pairs --output table

# Create key pair and save to file
aws ec2 create-key-pair \
  --key-name my-new-key \
  --query 'KeyMaterial' \
  --output text > my-new-key.pem
chmod 400 my-new-key.pem

# Import existing public key
aws ec2 import-key-pair \
  --key-name my-key \
  --public-key-material fileb://~/.ssh/id_rsa.pub
```

## AMI Management

```bash
# Find latest Amazon Linux 2023 AMI
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*" "Name=architecture,Values=x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name}' \
  --output table

# Find latest Ubuntu 22.04 AMI
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name}' \
  --output table

# Create AMI from running instance
aws ec2 create-image \
  --instance-id i-0123456789abcdef0 \
  --name "my-server-backup-$(date +%Y%m%d)" \
  --no-reboot
```
