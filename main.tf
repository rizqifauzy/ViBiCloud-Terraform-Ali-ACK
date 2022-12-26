resource "random_uuid" "this" {}
# The default resource names. 
locals {
  k8s_name_terway         = substr(join("-", [var.k8s_name_prefix,"terway"]), 0, 63)
  k8s_name_flannel        = substr(join("-", [var.k8s_name_prefix,"flannel"]), 0, 63)
  k8s_name_ask            = substr(join("-", [var.k8s_name_prefix,"ask"]), 0, 63)
  new_vpc_name            = "tf-ack-vpc"
  new_vsw_name_azA        = "tf-ack-vswitch-az-a"
  new_vsw_name_azB        = "tf-ack-vswitch-az-b"
  new_vsw_name_azC        = "tf-ack-vswitch-az-c"
  nodepool_name           = "tf-ack-nodepool"
  log_project_name        = "log-for-${local.k8s_name_terway}"
}

# The ECS instance specifications of the worker nodes. Terraform searches for ECS instance types that fulfill the CPU and memory requests. 
data "alicloud_instance_types" "default" {
  cpu_core_count       = 8
  memory_size          = 32
  availability_zone    = var.availability_zone[0]
  kubernetes_node_role = "Worker"
}
// The zone that has sufficient ECS instances of the required specifications. 
data "alicloud_zones" "default" {
  available_instance_type = data.alicloud_instance_types.default.instance_types[0].id
}
# The VPC. 
resource "alicloud_vpc" "default" {
  vpc_name   = local.new_vpc_name
  cidr_block = "172.16.0.0/12"
}
# The node vSwitch. 
resource "alicloud_vswitch" "vswitches" {
  count             = length(var.node_vswitch_ids) > 0 ? 0 : length(var.node_vswitch_cirds)
  vpc_id            = alicloud_vpc.default.id
  cidr_block        = element(var.node_vswitch_cirds, count.index)
  availability_zone = element(var.availability_zone, count.index)
}
# The pod vSwitch. 
resource "alicloud_vswitch" "terway_vswitches" {
  count             = length(var.terway_vswitch_ids) > 0 ? 0 : length(var.terway_vswitch_cirds)
  vpc_id            = alicloud_vpc.default.id
  cidr_block        = element(var.terway_vswitch_cirds, count.index)
  availability_zone = element(var.availability_zone, count.index)
}
# The ACK managed cluster. 
resource "alicloud_cs_managed_kubernetes" "default" {
  # The name of the cluster. 
  name                      = local.k8s_name_terway
  # Create an ACK Pro cluster. 
  cluster_spec              = "ack.pro.small"
  version                   = "1.24.6-aliyun.1"
  # The vSwitches of the new Kubernetes cluster. Specify one or more vSwitch IDs. The vSwitches must be in the zone specified by availability_zone. 
  worker_vswitch_ids        = split(",", join(",", alicloud_vswitch.vswitches.*.id))

  # The pod vSwitches. 
  pod_vswitch_ids           = split(",", join(",", alicloud_vswitch.terway_vswitches.*.id))

  # Specify whether to create a NAT gateway when the system creates the Kubernetes cluster. Default value: true. 
  new_nat_gateway           = true
  # The pod CIDR block. If you set cluster_network_type to flannel, this parameter is required. The pod CIDR block cannot be the same as the VPC CIDR block or the CIDR blocks of other Kubernetes clusters in the VPC. You cannot change the pod CIDR block after the cluster is created. Maximum number of hosts in the cluster: 256. 
  # pod_cidr                  = "10.10.0.0/16"
  # The Service CIDR block. The Service CIDR block cannot be the same as the VPC CIDR block or the CIDR blocks of other Kubernetes clusters in the VPC. You cannot change the Service CIDR block after the cluster is created. 
  service_cidr              = "10.11.0.0/16"
  # Specify whether to create an Internet-facing SLB instance for the API server of the cluster. Default value: false. 
  slb_internet_enabled      = true

  #Instance charges type
  #instance_charge_type  = "PostPaid"

  # Enable Ram Role for ServiceAccount
  enable_rrsa = true

  # The logs of the control plane. 
  control_plane_log_components = ["apiserver", "kcm", "scheduler"]

  # The components. 
  dynamic "addons" {
    for_each = var.cluster_addons
    content {
      name     = lookup(addons.value, "name", var.cluster_addons)
      config   = lookup(addons.value, "config", var.cluster_addons)
      # disabled = lookup(addons.value, "disabled", var.cluster_addons)
    }
  }

  runtime = {
    name    = "contianerd"
    version = "1.5.13"
  }
}

# The regular node pool. 
resource "alicloud_cs_kubernetes_node_pool" "default" {
  # The name of the cluster. 
  cluster_id            = alicloud_cs_managed_kubernetes.default.id
  # The name of the node pool. 
  name = local.nodepool_name
  # The vSwitches of the new Kubernetes cluster. Specify one or more vSwitch IDs. The vSwitches must be in the zone specified by availability_zone. 
  vswitch_ids           = split(",", join(",", alicloud_vswitch.vswitches.*.id))

  # Worker ECS Type and ChargeType
  # instance_types      = [data.alicloud_instance_types.default.instance_types[0].id]
  instance_types        = var.worker_instance_types
  instance_charge_type  = "PostPaid"
  #period                = 1
  #period_unit           = "Month"
  ##auto_renew            = true
  #auto_renew_period     = 1

  # customize worker instance name
  # node_name_mode      = "customized,ack-terway-shenzhen,ip,default"

  #Container Runtime
  runtime_name          = "containerd"
  runtime_version       = "1.5.13"

  # The number of worker nodes in the Kubernetes cluster. Default value: 3. Maximum value: 50. 
  desired_size          = 2
  # The password that is used to log on to the cluster by using SSH. 
  password              = var.password

  # Specify whether to install the CloudMonitor agent on the nodes in the cluster. 
  install_cloud_monitor = true

  # The type of the system disks of the nodes. Valid values: cloud_ssd and cloud_efficiency. Default value: cloud_efficiency. 
  system_disk_category  = "cloud_efficiency"
  system_disk_size      = 50

  # OS Type
  image_type            = "AliyunLinux"

  # Configurations of the data disks of the nodes. 
  #data_disks {
    # The disk type. 
  #  category = "cloud_essd"
    # The disk size. 
  #  size     = 120
  #}
}
