endpoints = {
    "s3"        = ["public", "privnat"]
    "dynamodb"  = ["public", "privnat"]
}
flowlog_retention = 90
stage = "dev"
enable_flowlog = false
project = "gitops-test"
cidr_block = "10.0.0.0/16"
subnets = {
    publicSubnet    = {cidr = "10.0.1.0/24", type = "public",  az = "ap-northeast-2a"},
    privnatSubnet-a = {cidr = "10.0.2.0/24", type = "privnat", az = "ap-northeast-2a"},
    privnatSubnet-c = {cidr = "10.0.3.0/24", type = "privnat", az = "ap-northeast-2c"},
    privateSubnet-a = {cidr = "10.0.4.0/24", type = "private", az = "ap-northeast-2a"},
    privateSubnet-c = {cidr = "10.0.5.0/24", type = "private", az = "ap-northeast-2c"},
}
region = "ap-northeast-2"
nacls = {}
region_code = "kr"
