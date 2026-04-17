# variables.tf

variable "services" {
  description = "Service group definitions. Keys are Harness service identifiers."
  type = map(object({
    container_port     = number
    health_check_path  = string
    host_header        = string
    task_role_arn      = string
    execution_role_arn = string
  }))

  validation {
    condition     = length(var.services) <= 48
    error_message = "Max 48 services per workspace. AWS ALB hard limit is 100 TGs/LB; with blue+green pattern that's 50 services. We cap at 48 across all envs for symmetry, leaving a 2-service buffer."
  }

  validation {
    condition     = length(distinct([for s in var.services : s.container_port])) == length(var.services)
    error_message = "Every service must have a unique container_port."
  }
}

variable "deployment_strategy" {
  type        = string
  description = "rolling for Dev/Test, blue_green for Prod. Drives whether green TGs are created and which override variables are pushed."

  validation {
    condition     = contains(["rolling", "blue_green"], var.deployment_strategy)
    error_message = "deployment_strategy must be 'rolling' or 'blue_green'."
  }
}

variable "vpc_name" {
  type        = string
  description = "Name tag of the VPC to place ALB and target groups in."

  validation {
    condition     = contains(["dev-workload", "gitops-hub-cluster"], var.vpc_name)
    error_message = "vpc_name must be 'dev-workload' or 'gitops-hub-cluster'."
  }
}

variable "env" {
  type        = string
  description = "Environment name used in resource naming (Dev / Test / Prod)."
}

# --- Harness variables ---

variable "harness_app_org" {
  type        = string
  default     = "business_unit_one"
  description = "Harness org where the application services live (override target)."
}

variable "harness_app_project" {
  type        = string
  default     = "ecs_project"
  description = "Harness project where the application services live (override target)."
}

variable "harness_app_env_id" {
  type        = string
  description = "Harness environment identifier for the overrides (Dev / Test / Prod)."
}

variable "harness_account_id" {
  type        = string
  description = "Harness account ID."
}
