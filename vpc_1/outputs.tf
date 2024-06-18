output "id" {
    description = <<-EOF
        description: vpc id
    EOF
    value = aws_vpc.main.id
}

output "subnet_ids" {
    description = <<-EOF
        description: vpc subnet id map
        ref_var_name: subnets
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_subnet.main: k => v.id }
}

output "rtb_ids" {
    description = <<-EOF
        description: vpc route table id map
        ref_var_name: subnets
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in local.subnets: k => v.type == "privnat" ? aws_route_table.main["${v.type}^${v.az}^${v.igw}"].id : aws_route_table.main[v.type].id }
}

output "natgw_public_ips" {
    description = <<-EOF
        description: nat gateway public ip address map
        ref_var_name: subnets
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: "type = privnat"
    EOF
    value = { for k, v in aws_eip.main: k => v.public_ip }
}

output "natgw_ids" {
    description = <<-EOF
        description: nat gateway ID map
        ref_var_name: subnets
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: "type = privnat"
    EOF
    value = { for k, v in aws_eip.main: k => v.id }
}

output "nacl_ids" {
    description = <<-EOF
        description: Network security group id map
        ref_var_name: nacls
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_network_acl.main: k => v.id }
}

output "gateway_endpoint_ids" {
    description = <<-EOF
        description: Gateway type VPC endpoint ids
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.gateway: k => v.id }
}

output "gateway_endpoint_arns" {
    description = <<-EOF
        description: Gateway type VPC endpoint arns
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.gateway: k => v.arn }
}

output "gateway_endpoint_prefixlist_ids" {
    description = <<-EOF
        description: prefix list ids for gateway type VPC endpoints
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.gateway: k => v.prefix_list_id }
}

output "gateway_endpoint_cidrs" {
    description = <<-EOF
        description: cidr blocks for gateway type VPC endpoints
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.gateway: k => v.cidr_blocks }
}

output "interface_endpoint_ids" {
    description = <<-EOF
        description: Interface type vpc endpoint ids
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.interface: k => v.id }
}

output "interface_endpoint_arns" {
    description = <<-EOF
        description: Interface type vpc endpoint arns
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.interface: k => v.arn }
}

output "interface_endpoint_dns_names" {
    description = <<-EOF
        description: dns names for interface type vpc endpoints
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.interface: k => v.dns_entry.*.dns_name }
}

output "interface_endpoint_hosted_zone_ids" {
    description = <<-EOF
        description: hosted zone ids for interface type vpc endpoints
        ref_var_name: endpoints
        ref_var_type: map
        ref_var_keys: null
        ref_var_filt: null
    EOF
    value = { for k, v in aws_vpc_endpoint.interface: k => v.dns_entry.*.hosted_zone_id }
}

output "interface_endpoint_sg_id" {
    description = <<-EOF
        description: Default security group ID for interface endpoint
    EOF
    value = one(aws_security_group.main.*.id)
}