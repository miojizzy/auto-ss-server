# Launch Template Management

Complete AWS CLI reference for EC2 launch templates.

## Listing & Describing Launch Templates

```bash
# List all launch templates
aws ec2 describe-launch-templates \
  --query 'LaunchTemplates[*].{ID:LaunchTemplateId,Name:LaunchTemplateName,DefaultVersion:DefaultVersionNumber,LatestVersion:LatestVersionNumber}' \
  --output table

# Get launch template details (all versions)
aws ec2 describe-launch-template-versions \
  --launch-template-id lt-0123456789abcdef0 \
  --output table

# Get specific version details
aws ec2 describe-launch-template-versions \
  --launch-template-id lt-0123456789abcdef0 \
  --versions '$Latest'

# Get the actual launch template data for a version
aws ec2 describe-launch-template-versions \
  --launch-template-id lt-0123456789abcdef0 \
  --versions '$Default' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData'
```

## Creating Launch Templates

```bash
# Create a basic launch template
aws ec2 create-launch-template \
  --launch-template-name my-app-template \
  --version-description "Initial version" \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "KeyName": "my-key-pair",
    "SecurityGroupIds": ["sg-0123456789abcdef0"],
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [{"Key": "Name", "Value": "my-app"}]
    }]
  }'

# Create launch template with full configuration
aws ec2 create-launch-template \
  --launch-template-name my-complete-template \
  --version-description "Full config" \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.small",
    "KeyName": "my-key-pair",
    "SecurityGroupIds": ["sg-0123456789abcdef0"],
    "UserData": "'$(base64 -w0 user-data.sh)'",
    "IamInstanceProfile": {"Name": "my-instance-profile"},
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 20,
        "VolumeType": "gp3",
        "DeleteOnTermination": true,
        "Encrypted": true
      }
    }],
    "Monitoring": {"Enabled": true},
    "TagSpecifications": [{
      "ResourceType": "instance",
      "Tags": [
        {"Key": "Name", "Value": "my-app"},
        {"Key": "Environment", "Value": "production"}
      ]
    }]
  }'
```

## Modifying Launch Templates

```bash
# Create a new version (only changes need to be specified)
aws ec2 create-launch-template-version \
  --launch-template-id lt-0123456789abcdef0 \
  --source-version '$Latest' \
  --version-description "Updated instance type" \
  --launch-template-data '{"InstanceType": "t3.medium"}'

# Update default version
aws ec2 modify-launch-template \
  --launch-template-id lt-0123456789abcdef0 \
  --default-version '3'

# Set default to latest
aws ec2 modify-launch-template \
  --launch-template-id lt-0123456789abcdef0 \
  --default-version '$Latest'

# Update launch template name
aws ec2 modify-launch-template \
  --launch-template-id lt-0123456789abcdef0 \
  # Note: Name cannot be changed after creation
```

## Deleting Launch Templates

```bash
# Delete a specific version
aws ec2 delete-launch-template-versions \
  --launch-template-id lt-0123456789abcdef0 \
  --versions '2' '3'

# Delete entire launch template (all versions)
aws ec2 delete-launch-template \
  --launch-template-id lt-0123456789abcdef0
```

## Using Launch Templates with Auto Scaling

```bash
# Create Auto Scaling Group with launch template
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --launch-template LaunchTemplateId=lt-0123456789abcdef0,Version='$Latest' \
  --min-size 1 \
  --max-size 5 \
  --desired-capacity 2 \
  --vpc-zone-identifier subnet-0123456789abcdef0,subnet-0fedcba9876543210

# Update ASG to use new template version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --launch-template LaunchTemplateId=lt-0123456789abcdef0,Version='$Latest'

# List Auto Scaling Groups using a template
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?LaunchTemplate.LaunchTemplateId==`lt-0123456789abcdef0`].AutoScalingGroupName' \
  --output text
```

## Spot Instances with Launch Templates

```bash
# Create launch template for Spot instances
aws ec2 create-launch-template \
  --launch-template-name my-spot-template \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "InstanceMarketOptions": {
      "MarketType": "spot",
      "SpotOptions": {
        "MaxPrice": "0.05",
        "SpotInstanceType": "persistent",
        "InstanceInterruptionBehavior": "stop"
      }
    }
  }'
```
