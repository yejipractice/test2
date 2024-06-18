########## Project Definition ########## {
variable "project" {
    description = <<-EOF
        description: Project name or service name
        type: string
        required: yes
        example: project = "gitops"
    EOF
    type = string
}

variable "stage" {
    description = <<-EOF
        description: Service stage of project (dev, stg, prd etc)
        type: string
        required: yes
        example: stage = "dev"
    EOF
    type = string
}

variable "region" {
    description = <<-EOF
        description: '''Region name to create resources
                     refer to https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html#Concepts.RegionsAndAvailabilityZones.Regions'''
        type: string
        required: yes
        default: ap-northeast-2
        example: region = "ap-northeast-2"
    EOF
    type    = string
}

variable "region_code" {
    description = <<-EOF
        description: '''Country code for region
                     refer to https://countrycode.org'''
        type: string
        required: yes
        default: kr
        example: region_code = "kr"
    EOF
    type = string
}
########## Project Definition ########## }

########## VPC Definition ########## {
variable "cidr_block" {
    description = <<-EOF
        description: Network CIDR block for VPC
        type: string
        required: yes
        example: cidr_block = "10.0.0.0/16"
    EOF
    type = string
}
########## VPC Definition ########## }

########## Subnet Definition ########## {
variable "subnets" {
    description = <<-EOF
        description: Subnet configuration (subnet name must not be same with subnet type)
        type: 
            map(object({
                cidr        = string # (required)
                type        = string # (required) public, privnat, private
                az          = string # (optional) subnet location (Availability zone)
                igw         = string # (optional) default route subnet (only for privnat type subnet)
            }))
        required: yes
        example: '''
            # For 3-tier muli-az network, 
            subnets = { 
                publicSubnet    = {cidr = "10.0.1.0/24", type = "public",  az = "ap-northeast-1a"},
                privnatSubnet-a = {cidr = "10.0.2.0/24", type = "privnat", az = "ap-northeast-1a", igw = "publicSubnet"},
                privnatSubnet-c = {cidr = "10.0.3.0/24", type = "privnat", az = "ap-northeast-1c", igw = "publicSubnet"},
                privateSubnet-a = {cidr = "10.0.4.0/24", type = "private", az = "ap-northeast-1a"},
                privateSubnet-c = {cidr = "10.0.5.0/24", type = "private", az = "ap-northeast-1c"}
            }
            # For 2-Tier single-az simple network,
            subnets = { 
                publicSubnet    = {cidr = "10.0.1.0/24", type = "public",  az = "ap-northeast-1a"},
                privateSubnet   = {cidr = "10.0.3.0/24", type = "private", az = "ap-northeast-1a"},
            }'''
    EOF
    type = any
    
    validation {
        condition = length([for k, v in var.subnets: k if k == v.type]) == 0
        error_message = "[ERROR] subnet name and type must be different"
    }
    validation {
        condition = length([for k, v in var.subnets: v.type if !contains(["public", "private", "privnat"], v.type)] ) == 0
        error_message = "[ERROR] subnet type must be one of public, privnat, private"
    }
    validation {
        condition = (length([for k, v in var.subnets: v.type if v.type == "privnat"]) > 0
                        ? length([for k, v in var.subnets: v.type if v.type == "public" ]) > 0
                            ? true 
                            : false 
                        : true
                    )
        error_message = "[ERROR] At least one public subnet required to create public NAT gateway"
    }
    validation {
        # 만일 privnat subnet의 default gw가 정의가 안되어 있으면, 1차로 public subnet중 동일한 az에 있는 subnet으로 설정하고, 그래도 없으면, 첫번째 public subnet으로 설정한다.
        condition = alltrue([for igw in [for subnet in var.subnets: 
                                          try(subnet.igw, coalescelist([for k, v in var.subnets: k if v.type == "public" && v.az == subnet.az], [for k, v in var.subnets: k if v.type == "public"])[0]) if subnet.type == "privnat"]:
                                contains([for k, v in var.subnets: k if v.type == "public"], igw) ? true : false])
        error_message = "[ERROR] default gateway for privnat subnet does not exists. please check again"
    }
}
########## Subnet Definition ########## }

########## Network ACL Definition ########## {
variable "nacls" {
    description = <<-EOF
        description: Network security group rule definition (name must be same with subnet name)
        type:  
            map(object({
                description     = string            #(Optional) Network ACL description
                ingresses       = list(object({     #(Optional) ingress rules definition
                    name        = string            #(Required) Network ACL inbound rule alias name
                    priority    = number            #(Required) 100 ~ 4096 rule priority
                    action      = string            #(Optinoal) Default action (allow/deny)
                    protocol    = string            #(Required) Protocol
                    dst_port_ranges = list(string)  #(Required) port ranges
                    cidr_block  = string            #(Required) CIDR blocs
                })))
                egresses = list(object({
                    name        = string            #(Required) Network ACL outbound rule alias name
                    priority    = number            #(Required) 100 ~ 4096 rule priority
                    action      = string            #(Optinoal) Default action (allow/deny)
                    protocol    = string            #(Required) Protocol
                    dst_port_ranges = list(string)  #(Required) port ranges
                    cidr_block  = string            #(Required) CIDR blocs
                })))
            }))
        required: no
        default: {}
        example: '''
            nacl_rules = {
                "publicSubnet" = { 
                    ingresses = [
                        {
                            name        = "sshInbound"
                            priority    = 100
                            action      = "allow"
                            protocol    = "tcp"
                            cidr_block  = "0.0.0.0/0"
                            dst_port_ranges = ["22", "2022"]
                            description = "allow ssh inbound traffic"
                        }
                    ]
                    egresses = [
                        {
                            name        = "allTcpOutbound"
                            priority    = 100
                            action      = "allow"
                            protocol    = "tcp"
                            cidr_block  = "0.0.0.0/0"
                            dst_port_ranges = ["0-65535"]
                            descriptoin = "allow all outbound tcp traffic"
                        }
                    ]
                }
            }'''
    EOF
    type = any
    default = {}
}
########## Network ACL Definition ########## }

########## Endpoint Service Definition ########## {
variable "endpoints" {
    description = <<-EOF
        description: '''gateway type and interface type vpc endpoint service definition
                     if subnet type is specified for values like endpoint = { s3 = ["public", "privnat"] } then creates s3 gateway type endpoint service
                     if subnet name is specified for values like endpoint = { s3 = ["privnatSubnet-a", "privnatSubnet-c"] } then creates interface type endpoint service'''
        type: map(list(string))
        required: no
        default: {}
        example: '''
            endpoints = {
                "s3"  = ["public", "privnat"]   # <= Subnet type list
                "sqs" = ["privnatSubnet-a", "privnatSubnet-c"] # <= Subnet name list
                "ses" = ["privateSubnet-a"] # <= Subnet name list
            }'''
    EOF
    type = map(list(string))
    default = {}
}
########## Endpoint Service Definition ########## }

########## Logging Definition ########## {
variable "enable_flowlog" {
    description = <<-EOF
        description: '''Enable network flowlog
                     if true, automatically creates cloudwatch log group for VPC flowlog'''
        type: bool
        required: no
        default: false
    EOF
    type = bool
    default = false
}

variable "flowlog_retention" {
    description = <<-EOF
        description: retention in days for cloudwatch log group of flowlog
        type: number
        required: no
        default: 90
    EOF
    type = number
    default = 90
}
########## Logging Definition ########## }