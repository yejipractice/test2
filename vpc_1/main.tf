provider "aws" {
    region = var.region
}

########## Local Block ########## {
locals {
    tag_suffix = "${var.project}_${var.stage}_${var.region_code}"
    # only 1 natgw per az
    
    public_subnets  = {for k, v in var.subnets: k => v if v.type == "public"}
    privnat_subnets = {for k, v in var.subnets: k => v if v.type == "privnat"}
    subnets = { for name, subnet in var.subnets: name => subnet.type != "privnat" ? subnet :
                { 
                    cidr = subnet.cidr
                    type = subnet.type
                    az   = subnet.az
                    igw   = try(subnet.igw, coalescelist([for k, v in local.public_subnets: k if v.az == subnet.az], keys(local.public_subnets))[0])
                }
    }
    
    # 만일 privnat subnet의 default gw가 정의가 안되어 있으면, 1차로 public subnet중 동일한 az에 있는 subnet으로 설정하고, 그래도 없으면, 첫번째 public subnet으로 설정한다.
    natgw_public_subnet_ids  = toset([for k, v in local.subnets: v.igw if v.type == "privnat"])
    gateway_endpoints   = {for k, v in {for k, v in var.endpoints: k => [for t in v: t if contains(["public", "privnat"], t)] if contains(["s3", "dynamodb"], k)}: k => v if length(v) > 0}
    interface_endpoints = {for k, v in {for k, v in var.endpoints: k => [for s in v: s if contains(keys(aws_subnet.main), s)]}: k => v if length(v) > 0}
}
########## Local Block ########## }

########## VPC Network Blcok ########## {
resource "aws_vpc" "main" {
    cidr_block = var.cidr_block
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = {
        Name = format("vpc_%s", local.tag_suffix)
    }
    # kubernetes tag 때문에 추가, k8s가 추가한 tag 자동 삭제 방지용
    lifecycle {
        ignore_changes = [tags]
    }
    
    depends_on= [aws_cloudwatch_log_group.main]
}

resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id
    tags = {
        "Name" = format("igw_%s", local.tag_suffix)
        "vpc_id" = aws_vpc.main.id
    }
}

resource "aws_subnet" "main" {
    for_each = local.subnets
    vpc_id = aws_vpc.main.id
    cidr_block = each.value.cidr
    availability_zone = each.value.az
    tags = {
        "Name" = format("sub_%s_%s%s", each.key, local.tag_suffix, substr(each.value.az, -1, 1))
        "vpc_id" = aws_vpc.main.id
        "az_name" = each.value.az
        "default_gateway" = (split("^", each.key)[0] == "privnat" ? split("^", each.key)[2]
                                : split("^", each.key)[0] == "public" ? aws_internet_gateway.main.id
                                : "None")
    }
    # kubernetes tag 때문에 추가, k8s가 추가한 tag 자동 삭제 방지용
    lifecycle {
        ignore_changes = [tags]
    }
}

resource "aws_route_table" "main" {
    for_each = toset([for k, v in local.subnets: v.type == "privnat" ? "${v.type}^${v.az}^${v.igw}" : v.type])

    vpc_id = aws_vpc.main.id
    
    dynamic "route" {
        for_each = ( split("^", each.key)[0] == "public" ?  [aws_internet_gateway.main.id] :
                     split("^", each.key)[0] == "privnat" ? [aws_nat_gateway.main[split("^", each.key)[2]].id] : []
                   )
        content {
            cidr_block = "0.0.0.0/0"
            gateway_id = route.value
        }
    }
    tags = {
        "Name" = (strcontains(each.key, "privnat") ?
                    format("rtb_%s_%s%s", split("^", each.key)[0], local.tag_suffix, substr(split("^", each.key)[1], -1, 1))
                    : format("rtb_%s_%s", split("^", each.key)[0], local.tag_suffix))
        "vpc_id" = aws_vpc.main.id
        "default_gateway" = (split("^", each.key)[0] == "privnat" 
                                ? format("%s (%s)", aws_nat_gateway.main[split("^", each.key)[2]].id, split("^", each.key)[2])
                                : split("^", each.key)[0] == "public" 
                                    ? aws_internet_gateway.main.id
                                    : "None")
    }
    lifecycle {
        ignore_changes = [route]
    }
}

resource "aws_route_table_association" "main" {
    for_each = {for k, v in local.subnets: k => v.type == "privnat" ? "${v.type}^${v.az}^${v.igw}" : v.type}
    subnet_id = aws_subnet.main[each.key].id
    route_table_id = aws_route_table.main[each.value].id
}
########## VPC Network Block ########## }

########## VPC NAT Gateway Block ########## {
resource "aws_eip" "main" {
    for_each = local.natgw_public_subnet_ids
    domain = "vpc"
    tags = {
        # Naming rule: eip_natgw_[svc]_[purpose]_[env]_[az]_[region] ex) eip_natgw_dks_svc_prod_kr
        "Name" = format("eip_natgw_%s%s", local.tag_suffix, substr(aws_subnet.main[each.key].availability_zone, -1, 1))
        "vpc_id" = aws_vpc.main.id
        "subnet_name" = each.key
    }
}

resource "aws_nat_gateway" "main" {
    for_each = local.natgw_public_subnet_ids
    connectivity_type = "public" # public for internet, private for other vpcs (private connectivity_type not supported now)
    
    allocation_id = aws_eip.main[each.key].allocation_id
    subnet_id = aws_subnet.main[each.value].id
    tags = {
        # Naming rule: natgw_[service name]_[purpose]_[env]_[az]_[region] ex) natgw_dks_svc_prod_a_kr
        "Name"      = format("natgw_%s%s", local.tag_suffix, substr(aws_subnet.main[each.key].availability_zone, -1, 1))
        "vpc_id"    = aws_vpc.main.id
        "eip_id"    = aws_eip.main[each.key].id
        "default_gateway" = each.key
    }
    depends_on = [aws_internet_gateway.main]
}
########## VPC NAT Gateway Block ########## }

########## VPC NALC Block ########## {
resource "aws_network_acl" "main" {
    for_each = var.nacls
    vpc_id = aws_vpc.main.id
    subnet_ids = [ aws_subnet.main[each.key].id ]

    dynamic "ingress" {
        for_each = try(each.value.ingresses, [])
        content {
            protocol = ingress.value.protocol
            rule_no = ingress.value.priority
            action = ingress.value.action
            cidr_block = ingress.value.cidr_block
            from_port = length(split("-", ingress.value.dst_port_ranges[0])) > 1 ? tonumber(split("-", ingress.value.dst_port_ranges[0])[0]) : tonumber(ingress.value.dst_port_ranges[0])
            to_port = length(split("-", ingress.value.dst_port_ranges[0])) > 1 ? tonumber(split("-", ingress.value.dst_port_ranges[0])[1]) : tonumber(ingress.value.dst_port_ranges[0])
        }
    }
    dynamic "egress" {
        for_each = try(each.value.egresses, [])
        content {
            protocol = egress.value.protocol
            rule_no = egress.value.priority
            action = egress.value.action
            cidr_block = egress.value.cidr_block
            from_port = length(split("-", egress.value.dst_port_ranges[0])) > 1 ? tonumber(split("-", egress.value.dst_port_ranges[0])[0]) : tonumber(egress.value.dst_port_ranges[0])
            to_port = length(split("-", egress.value.dst_port_ranges[0])) > 1 ? tonumber(split("-", egress.value.dst_port_ranges[0])[1]) : tonumber(egress.value.dst_port_ranges[0])
        }
    }
    tags = {
        "Name" = format("nacl_%s_%s", each.key, local.tag_suffix)
        "vpc_id" = aws_vpc.main.id
        "subnet_names" = join(",", [each.key])
        "subnet_ids" = join(",", [aws_subnet.main[each.key].id])
    }
}
########## VPC NALC Block ########## }
resource "aws_security_group" "main" {
    count           = length(local.interface_endpoints) > 0 ? 1 : 0
    name            = "ep_default_${local.tag_suffix}"
    description     = "default security group for interface endpoint"
    vpc_id          = aws_vpc.main.id
    tags            = {
        "Name" = "ep_default_${local.tag_suffix}"
        "vpc_id" = aws_vpc.main.id
    }
}

resource "aws_security_group_rule" "main" {
    count               = length(local.interface_endpoints) > 0 ? 1 : 0
    security_group_id   = one(aws_security_group.main.*.id)
    description         = "allow https 443 tcp inbound traffic"
    type                = "ingress"
    protocol            = "tcp"
    from_port           = 443
    to_port             = 443
    cidr_blocks         = [ var.cidr_block ]
}

resource "aws_vpc_endpoint" "gateway" {
    for_each = local.gateway_endpoints
    vpc_id = aws_vpc.main.id
    service_name = "com.amazonaws.${var.region}.${each.key}"
    
    vpc_endpoint_type = "Gateway"
    auto_accept = true
    policy = null
    route_table_ids = flatten([ for type in each.value:
                           [ for rt_name, rt_value in aws_route_table.main: rt_value.id if strcontains(rt_name, type) ]
                      ])
    tags = {
        "Name" = format("ep-gtw_%s_%s", each.key, local.tag_suffix)
        "vpc_id" = aws_vpc.main.id
        "type" = "gateway"
        "rtb_ids" = join(",", flatten([ for type in each.value:
                           [ for rt_name, rt_value in aws_route_table.main: rt_value.id if strcontains(rt_name, type) ]
                    ]))
    }
    
    depends_on = [aws_route_table_association.main]
}

resource "aws_vpc_endpoint" "interface" {
    for_each = local.interface_endpoints
    vpc_id = aws_vpc.main.id
    service_name = "com.amazonaws.${var.region}.${each.key}"
    
    vpc_endpoint_type = "Interface"
    auto_accept = true
    private_dns_enabled = true

    subnet_ids = [for name in each.value: aws_subnet.main[name].id]
    security_group_ids = [one(aws_security_group.main.*.id)]

    # s3, dynamodb와 같이 gateway, interface type의 endpoint가 모두 있는경우, VPC내 traffic은 gateway type으로 onprem으로 부터의 traffic은 intertace로 자동 route
    # network cost를 save할 수 있는 option이며, true인 경우, 반드시 해당 서비스에 대한 gateway endpoint가 있어야만 합니다.
    # provider version 5.0 이상에서 update 됨
    dynamic "dns_options" {
        for_each = contains(keys(aws_vpc_endpoint.gateway), each.key) ? [true] : [false]
        content {
            private_dns_only_for_inbound_resolver_endpoint = dns_options.value
        }
    }
    
    tags = {
        "Name" = format("ep-inf_%s_%s", each.key, local.tag_suffix)
        "vpc_id" = aws_vpc.main.id
        "type" = "interface"
        "subnet_ids" = join(",", [for name in each.value: "${aws_subnet.main[name].id} (${name})"])
    }
    # check DuplicateSubnetsInSameZone error
    lifecycle {
        precondition {
            condition = length([for name in each.value: aws_subnet.main[name].id]) == length(distinct([for name in each.value: aws_subnet.main[name].availability_zone]))
            error_message = "[ERROR] DuplicateSubnetsInSameZone. VPC endpoint subnets should be in different availability zones"
        }
    }
    depends_on = [aws_route_table_association.main, aws_vpc_endpoint.gateway]
}
########## VPC Endpoint Block ########## }

########## VPC Flowlog Block ########## {
resource "aws_cloudwatch_log_group" "main" {
    for_each = var.enable_flowlog ? toset(["flowlog"]) : toset([])
    name = "/aws/flowlog/${local.tag_suffix}"
    retention_in_days = var.flowlog_retention
    tags = {
        "Name" = "/aws/flowlog/${local.tag_suffix}"
    }
}

resource "aws_iam_role" "main" {
    for_each = var.enable_flowlog ? toset(["flowlog"]) : toset([])
    name = "r_flowlog_${local.tag_suffix}"
    assume_role_policy = <<-EOF
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Sid": "",
              "Effect": "Allow",
              "Principal": {
                "Service": "vpc-flow-logs.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }
    EOF
    tags = {
        "Name" = "r_flowlog_${local.tag_suffix}"
    }
}
    
resource "aws_iam_role_policy" "main" {
    for_each = var.enable_flowlog ? toset(["flowlog"]) : toset([])
    name = "p_flowlog_${local.tag_suffix}"
    role = aws_iam_role.main["flowlog"].id
    policy = <<-EOF
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
              ],
              "Effect": "Allow",
              "Resource": "*"
            }
          ]
        }
    EOF
}

resource "aws_flow_log" "main" {
    for_each = var.enable_flowlog ? toset(["flowlog"]) : toset([])
    vpc_id = aws_vpc.main.id
    iam_role_arn = aws_iam_role.main["flowlog"].arn
    log_destination = aws_cloudwatch_log_group.main["flowlog"].arn
    traffic_type = "ALL"
    max_aggregation_interval = 600 #default
    # destination_options {
    #     file_format = "plain-text"
    #     hive_compatible_partitions = false
    #     per_hour_partition = false
    # }
    tags = {
        "Name" = "flowlog_${local.tag_suffix}"
        "vpc_id" = aws_vpc.main.id
        "cw_log_group" = aws_cloudwatch_log_group.main["flowlog"].arn
        "iam_role_arn" = aws_iam_role.main["flowlog"].arn
    }
    depends_on = [ aws_vpc.main ]
}
########## VPC Flowlog Block ########## }