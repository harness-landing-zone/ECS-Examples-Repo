# ECS Service Group Workspace — Test Scaffold

Test scaffold proving the "one IACM workspace per environment owns a group of ECS services" pattern for Harness IACM ECS onboarding.

## What This Test Proves

1. **Cross-org override creation** — A single OpenTofu run in `infrastructure_org/ecs_project` creates `harness_platform_service_overrides_v2` resources targeting services in `business_unit_one/ecs_project`. Validates that the Harness provider can write overrides cross-org.

2. **Rolling vs blue/green branching** — `deployment_strategy` variable drives:
   - Rolling (Dev/Test): 1 TG per service, override pushes `target_group_arn` only.
   - Blue/green (Prod): 2 TGs per service, override pushes `target_group_arn` (blue), `stage_target_group_arn` (green), and `prod_listener_arn`.

3. **Hardcoded ARN injection** — Override YAML contains literal AWS ARNs rendered by `templatefile()`. Validates that Terraform-rendered ARNs work in override YAML without needing `<+workspace.X.outputs.Y>` cross-project expressions.

4. **48-service precondition** — Variable validation enforces a 48-service ceiling (100 TGs / ALB / 2 TGs per service in blue/green = 50 max, minus 2-service buffer).

5. **ignore_changes for blue/green listener weights** — `lifecycle { ignore_changes = [action] }` prevents Terraform from reverting Harness-managed traffic weights after the initial apply.

## State Management

State is managed by the Harness IACM workspace — there is **no backend block** in the code. The workspace injects the state backend, AWS credentials, and Harness API key automatically.

Do not add a `backend {}` block or configure remote state (GCS/S3).

## How to Run

### Prerequisites

```bash
export HARNESS_PLATFORM_API_KEY="your-api-key"
export HARNESS_ACCOUNT_ID="qIYsos1ZQO6fJMG1Ip6KJA"
export AWS_PROFILE="your-profile"  # Or use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
```

### Dev (Rolling)

```bash
tofu init
tofu plan  -var-file=terraform.tfvars.dev.example
tofu apply -var-file=terraform.tfvars.dev.example
```

### Prod (Blue/Green)

```bash
tofu init
tofu plan  -var-file=terraform.tfvars.prod.example
tofu apply -var-file=terraform.tfvars.prod.example
```

## How to Verify Success

### Dev (Rolling)

- BU1 override exists with `target_group_arn` = literal blue TG ARN.
- Override does **not** contain `stage_target_group_arn`.
- Green target groups are **not** created.
- Listener rules forward to blue TG only (no weighted routing).

### Prod (Blue/Green)

- BU1 override exists with `target_group_arn` (blue), `stage_target_group_arn` (green), and `prod_listener_arn`.
- Green target groups exist for every service.
- Listener rules have weighted forward: blue 100 / green 0.
- **Idempotency check**: Run `tofu apply` a second time with no service changes — confirm it is a no-op (validates `ignore_changes`).

## Known Limits

| Limit | Detail |
|-------|--------|
| 48-service ceiling | Symmetric across envs. Prod blue/green uses 2 TGs/service (100 TG/ALB limit = 50 max, minus 2 buffer). |
| Single-ALB blast radius | All services in the group share one ALB. ALB failure takes down the group. |
| Listener weights not Terraform-owned in Prod | After first apply, `action` block is ignored. Taint the listener rule to force recreation if TG config changes. |
| `ignore_changes` always set | Applied in both strategies because `lifecycle` cannot be conditional. Harmless in rolling (no runtime weight changes). |

## File Layout

```
providers.tf                     # terraform block (no backend), AWS + Harness providers
variables.tf                     # services map, deployment_strategy, env, VPC, Harness vars
locals.tf                        # is_blue_green, TG name truncation, listener priorities
security_groups.tf               # ALB SG + ECS tasks SG
alb.tf                           # Internal ALB + HTTP listener (404 default)
target_groups.tf                 # Blue TGs (always) + Green TGs (blue_green only)
listener_rules.tf                # Per-service rules with conditional weighted routing
harness_overrides.tf             # Cross-org service overrides via templatefile()
templates/override.yaml.tftpl    # Override YAML template (branches on is_blue_green)
outputs.tf                       # ALB DNS/ARN, listener ARN, per-service resource map
terraform.tfvars.dev.example     # Dev/rolling example (3 services)
terraform.tfvars.prod.example    # Prod/blue_green example (3 services)
```
