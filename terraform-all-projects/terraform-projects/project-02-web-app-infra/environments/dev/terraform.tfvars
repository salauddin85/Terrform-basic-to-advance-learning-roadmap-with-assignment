project     = "webapp"
environment = "dev"
aws_region  = "us-east-1"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
enable_nat_gateway   = false # set true when EC2 needs outbound internet access

# Compute
instance_type        = "t3.micro"
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 2
health_check_path    = "/"

# Database
db_name                  = "appdb"
db_username              = "appuser"
db_instance_class        = "db.t3.micro"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 7
