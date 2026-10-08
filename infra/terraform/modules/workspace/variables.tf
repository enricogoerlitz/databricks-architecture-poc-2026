variable "prefix" { type = string }
variable "env" { type = string }
variable "index" {
  description = "Zweistellig, z. B. 01"
  type        = string
}
variable "suffix" { type = string }
variable "location" { type = string }
variable "location_short" { type = string }
variable "subscription_id" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_id" { type = string }
variable "vnet_name" { type = string }
variable "host_cidr" { type = string }
variable "container_cidr" { type = string }
variable "pe_subnet_id" { type = string }
variable "nat_gateway_id" { type = string }
variable "access_connector_id" { type = string }
variable "private_dns_zone_ids" {
  description = "Map subresource (dfs, blob) => Private DNS Zone ID"
  type        = map(string)
}
variable "tags" { type = map(string) }
