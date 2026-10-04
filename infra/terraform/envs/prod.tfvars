env                = "prod"
region             = "ap-south-1"
vpc_cidr           = "10.60.0.0/16"
az_count           = 3
single_nat_gateway = false # one NAT per AZ, so an AZ failure does not cut egress
enable_secrets     = false

services = {
  "payment-service" = {
    short_name  = "pay"
    desired     = 3
    cpu         = 512
    memory      = 1024
    paths       = ["/payments", "/payments/*"]
    health_path = "/payments/healthz"
    priority    = 10
  }
  "reconciliation-service" = {
    short_name  = "recon"
    desired     = 3
    cpu         = 512
    memory      = 1024
    paths       = ["/reconciliation", "/reconciliation/*"]
    health_path = "/reconciliation/healthz"
    priority    = 20
  }
}
