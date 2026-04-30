# Elastic IP (Public IP) Management

Complete AWS CLI reference for managing Elastic IPs and public IP addresses.

## Listing Elastic IPs

```bash
# List all Elastic IPs
aws ec2 describe-addresses \
  --query 'Addresses[*].{
    AllocationId:AllocationId,
    PublicIP:PublicIp,
    PrivateIP:PrivateIpAddress,
    InstanceId:InstanceId,
    AssociationId:AssociationId,
    Domain:Domain
  }' \
  --output table

# Check if an Elastic IP is associated
aws ec2 describe-addresses \
  --public-ips 203.0.113.100

# List unassociated Elastic IPs (not attached to any instance)
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].{AllocationId:AllocationId,PublicIP:PublicIp}' \
  --output table

# Find Elastic IP by allocation ID
aws ec2 describe-addresses \
  --allocation-ids eipalloc-0123456789abcdef0
```

## Allocating Elastic IPs

```bash
# Allocate a new Elastic IP for VPC use
aws ec2 allocate-address --domain vpc

# Allocate with a name tag
ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --query 'AllocationId' \
  --output text)

aws ec2 create-tags \
  --resources $ALLOC_ID \
  --tags Key=Name,Value=my-server-eip

echo "Allocated: $ALLOC_ID"

# Allocate from a specific address pool (BYOIP)
aws ec2 allocate-address \
  --domain vpc \
  --public-ipv4-pool ipv4pool-ec2-0123456789abcdef0
```

## Associating Elastic IPs

```bash
# Associate with an EC2 instance
aws ec2 associate-address \
  --instance-id i-0123456789abcdef0 \
  --allocation-id eipalloc-0123456789abcdef0

# Associate with a network interface
aws ec2 associate-address \
  --network-interface-id eni-0123456789abcdef0 \
  --allocation-id eipalloc-0123456789abcdef0

# Associate and allow reassociation (overwrite existing association)
aws ec2 associate-address \
  --instance-id i-0123456789abcdef0 \
  --allocation-id eipalloc-0123456789abcdef0 \
  --allow-reassociation
```

## Disassociating Elastic IPs

```bash
# Disassociate from instance (keep the Elastic IP)
aws ec2 disassociate-address \
  --association-id eipassoc-0123456789abcdef0

# Get association ID from allocation ID first
ASSOC_ID=$(aws ec2 describe-addresses \
  --allocation-ids eipalloc-0123456789abcdef0 \
  --query 'Addresses[0].AssociationId' \
  --output text)
aws ec2 disassociate-address --association-id $ASSOC_ID
```

## Releasing Elastic IPs

```bash
# Release an Elastic IP (billing stops, IP returned to AWS pool)
# CAUTION: If you re-allocate, you may not get the same IP back
aws ec2 release-address --allocation-id eipalloc-0123456789abcdef0

# Release all unassociated Elastic IPs (CAUTION: non-recoverable)
for alloc_id in $(aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].AllocationId' \
  --output text); do
  echo "Releasing $alloc_id"
  aws ec2 release-address --allocation-id $alloc_id
done
```

## Auto-assign Public IPs (Non-Elastic)

```bash
# Check if a subnet auto-assigns public IPs
aws ec2 describe-subnets \
  --subnet-ids subnet-0123456789abcdef0 \
  --query 'Subnets[0].{ID:SubnetId,AutoAssignPublicIP:MapPublicIpOnLaunch}'

# Enable auto-assign public IP for a subnet
aws ec2 modify-subnet-attribute \
  --subnet-id subnet-0123456789abcdef0 \
  --map-public-ip-on-launch

# Launch instance with public IP assigned (when subnet doesn't auto-assign)
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --network-interfaces '[{
    "DeviceIndex": 0,
    "SubnetId": "subnet-0123456789abcdef0",
    "AssociatePublicIpAddress": true,
    "Groups": ["sg-0123456789abcdef0"]
  }]'
```

## Cost Optimization

```bash
# List Elastic IPs costing money (allocated but not associated)
# AWS charges ~$0.005/hour for unassociated Elastic IPs
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].{AllocationId:AllocationId,PublicIP:PublicIp}' \
  --output table

# Check how many Elastic IPs you have (default limit is 5 per region)
aws ec2 describe-addresses \
  --query 'length(Addresses)' \
  --output text
```

## Elastic IP Limits & Quotas

```bash
# Check EC2 service quotas for Elastic IPs
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0263D0A3

# Request a quota increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-0263D0A3 \
  --desired-value 10
```
