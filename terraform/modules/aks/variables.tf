variable "cluster_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "aks_subnet_id" {
  type = string
}

variable "service_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "10.30.0.10"
}

variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "system_node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "system_min_count" {
  type    = number
  default = 3
}

variable "system_max_count" {
  type    = number
  default = 5
}

variable "user_node_vm_size" {
  type    = string
  default = "Standard_D8s_v5"
}

variable "user_min_count" {
  type    = number
  default = 3
}

variable "user_max_count" {
  type    = number
  default = 10
}

variable "admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "AAD groups granted cluster-admin via Azure AD-integrated RBAC."
}

variable "tenant_id" {
  type = string
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
