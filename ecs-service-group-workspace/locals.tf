# locals.tf

locals {
  is_blue_green = var.deployment_strategy == "blue_green"

  # Symmetric capacity across envs: 48 service hard cap regardless of strategy.
  # Prod is bound by 100 TG / ALB / 2 TGs per service = 50; we leave 2-service buffer.

  # TG names must be <= 32 chars (AWS limit). # Confirmed: AWS docs.
  # Format: {env}-{service_key}-b or -g, truncated to 32.
  tg_names_blue = {
    for key, svc in var.services : key => substr("${var.env}-${key}-b", 0, 32)
  }
  tg_names_green = {
    for key, svc in var.services : key => substr("${var.env}-${key}-g", 0, 32)
  }

  # Listener rule priorities: assign sequentially starting at 100.
  # Using zipmap with sorted keys for deterministic ordering.
  service_keys_sorted = sort(keys(var.services))
  service_priorities = {
    for idx, key in local.service_keys_sorted : key => 100 + idx
  }
}
