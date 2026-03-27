# Harness ECS Fargate Landing Zone

A reference implementation for deploying **100+ microservices** to AWS ECS Fargate using Harness CD. One pipeline, N services, N triggers, per-environment overrides. Linear scaling — every new service is three files, zero pipeline changes.

## How It Works

```
ECR push (app1:42)
  --> per-service trigger (ecs-app1.yaml)
    --> golden pipeline (ecs-deploy.yaml) with serviceRef=ecs_app1_service, tag=42
      --> Deploy DEV (EcsRollingDeploy + health check)
        --> Release Manager Approval (4h timeout)
          --> Deploy PROD (same image, same service, EcsRollingDeploy + health check)
```

Every microservice follows this exact flow. The pipeline never changes — service identity, sizing, and networking are resolved at runtime from Harness Service variables and environment overrides.

## Repository Structure

```
.harness/orgs/business_unit_one/projects/ecs_project/
  services/                     # One YAML per microservice (Harness Service definitions)
    ecs-service-app1.yaml       #   app1: greeting-service, 512 CPU / 1024 MiB
    ecs-service-app2.yaml       #   app2: inventory-service, 1024 CPU / 2048 MiB
  pipelines/
    ecs-deploy.yaml             # Golden pipeline: DEV -> Approval -> PROD
  triggers/                     # One ECR trigger per microservice
    ecs-app1.yaml               #   Watches app1 ECR repo, fires pipeline with serviceRef=ecs_app1_service
    ecs-app2.yaml               #   Watches app2 ECR repo, fires pipeline with serviceRef=ecs_app2_service
  envs/                         # Harness Environment definitions
    pre_production/Dev.yaml
    production/prod.yaml
  overrides/                    # Global Environment overrides (networking, IAM, ECR account)
    Dev/Dev.yaml
    Prod/Prod.yaml

ecs-global-configs/             # ECS manifest templates (shared across all services)
  shared/
    taskdef.yaml                # Fargate task definition — all values from Harness expressions
    servicedef.yaml             # ECS service definition — rolling deploy, circuit breaker
    scalable-target.yaml        # Auto-scaling min/max from service variables
    scaling-policy.yaml         # CPU target-tracking at 70%
  app2/
    taskdef.yaml                # Per-service override (only if custom container config needed)

app-example/                    # Sample Spring Boot apps (for building container images)
  app1/                         # greeting-service (Java 17, Spring Boot, /actuator/health)
  app2/                         # inventory-service (Java 17, Spring Boot, /actuator/health)
```

The `.harness/` folder follows [Harness Git Experience](https://developer.harness.io/docs/platform/git-experience/) conventions. Services, pipelines, environments, and overrides are stored in Git with paths mirroring the Harness org/project hierarchy.

## Architecture

### Golden Pipeline Pattern

One pipeline serves all services. Service identity is injected at runtime:

| Component | Count | Changes when adding a service? |
|---|---|---|
| Pipeline (`ecs-deploy.yaml`) | 1 | No |
| Shared manifests (`ecs-global-configs/shared/`) | 4 files | No |
| Harness Service YAML | 1 per service | **Yes** -- create one |
| ECR trigger | 1 per service | **Yes** -- create one |
| Global Environment override | 1 per env | No |
| Service Specific override (prod sizing) | 0-1 per service | Only if prod sizing differs from defaults |

### Service Variable Tiers

Each Harness Service defines variables consumed by the ECS manifest templates:

| Tier | Variables | Where Set |
|---|---|---|
| **Identity** | `service_name` | Hardcoded in service YAML (`required: true`) |
| **Sizing** | `cpu`, `memory`, `desired_count`, `min_capacity`, `max_capacity`, `container_port` | Defaults in service YAML; overridden per env |
| **Networking** | `subnet_1`, `subnet_2`, `security_group`, `assign_public_ip`, `execution_role_arn`, `task_role_arn` | Empty in service YAML; **must** be set via environment override |
| **Runtime** | `ecr_registry_id` | `<+input>` -- provided by trigger or manual input |

Networking variables are intentionally empty. A deployment to an environment without overrides fails immediately rather than silently using wrong infrastructure.

### Override Strategy

| Override Type | What It Sets | Scales With |
|---|---|---|
| **Global Environment** | Subnets, security groups, IAM roles, ECR account ID | 1 per environment (shared by all services) |
| **Service Specific** | CPU, memory, scaling, target group ARN | Only services whose prod sizing differs from defaults |

Override precedence (highest wins): Infra+Service Specific > Infra Specific > Service Specific > Global Environment.

### Failure Strategy

- **ECS deploy steps**: `StageRollback` on all errors. Never step retry.
- **Rollback steps**: `EcsRollingRollback` restores the previous task definition.
- **Approval timeout**: 4 hours, then pipeline fails. Never auto-promotes to prod.
- **Health checks**: curl-based, retry up to 10 (DEV) / 12 (PROD) attempts at 15s intervals.

## Adding a New Service

To onboard `app3`, create these files and nothing else:

### 1. Service YAML

**`.harness/orgs/business_unit_one/projects/ecs_project/services/ecs-service-app3.yaml`**

Copy `ecs-service-app1.yaml` and change:
- `name: ecs-app3-service`, `identifier: ecs_app3_service`
- `service_name` value: `app3`
- `cpu` / `memory` / `desired_count`: set appropriate defaults
- Artifact `imagePath`: `<+input>` (resolved at runtime)

### 2. ECR Trigger

**`.harness/orgs/business_unit_one/projects/ecs_project/triggers/ecs-app3.yaml`**

Copy `ecs-app1.yaml` and change:
- `imagePath: app3` (must match ECR repo name)
- `serviceRef: ecs_app3_service` in inputYaml (must match service identifier)

### 3. Prod Override (optional)

Only needed if app3's production sizing differs from its service-level defaults. Create a **Service Specific Override** (`ENV_SERVICE_OVERRIDE`) for the Prod environment with the service's cpu, memory, and scaling values.

Networking is already handled by the Global Environment override -- no per-service networking config needed.

**That's it.** No pipeline changes. No manifest changes. No environment changes.

## Manifest Templates

All templates in `ecs-global-configs/shared/` are parameterised with Harness expressions:

| Template | Key Expressions |
|---|---|
| `taskdef.yaml` | `<+serviceVariables.service_name>`, `<+artifacts.primary.image>`, `<+serviceVariables.cpu>`, `<+serviceVariables.execution_role_arn>` |
| `servicedef.yaml` | `<+serviceVariables.desired_count>`, `<+serviceVariables.subnet_1>`, `<+serviceVariables.assign_public_ip>` |
| `scalable-target.yaml` | `<+serviceVariables.min_capacity>`, `<+serviceVariables.max_capacity>` |
| `scaling-policy.yaml` | `<+serviceVariables.service_name>`, CPU target 70%, cooldowns 60s/300s |

If a service needs a custom task definition (sidecars, different health check, extra env vars), create `ecs-global-configs/<app>/taskdef.yaml` and update the service's manifest path. The shared templates remain unchanged.

## Pipeline Stages

| Stage | Type | Environment | Key Behaviour |
|---|---|---|---|
| **Deploy DEV** | EcsRollingDeploy | Dev / ECS_Dev | Rolling deploy + health check. StageRollback on failure. |
| **Promote to Prod** | HarnessApproval | -- | Release Managers approve within 4h. Shows service name, image, and task def ARN. |
| **Deploy PROD** | EcsRollingDeploy | Prod / ECS_Prod | `useFromStage: deploy_dev` (same service + artifact). StageRollback on failure. |

Notifications go to Slack on pipeline start, success, failure, and stage failure.

## Trigger Configuration

Each trigger watches one ECR repository and fires the golden pipeline:

| Field | Purpose |
|---|---|
| `imagePath` | ECR repo name -- must match exactly (e.g. `app1`) |
| `eventConditions: ^\d+$` | Only numeric tags trigger deploys (filters out `latest`, branch tags) |
| `autoAbortPreviousExecutions: true` | Cancels in-flight run if a newer image is pushed |
| `inputYaml.serviceRef` | Which Harness Service to deploy (e.g. `ecs_app1_service`) |
| `inputYaml.tag` | `<+trigger.artifact.build>` -- the new image tag |
| `inputYaml.ecr_registry_id` | `<+variable.ecr_registry_id>` -- AWS account ID from project variable |

The pipeline also supports **manual execution** where these values are provided as runtime inputs.

## Prerequisites

Before deploying, ensure these exist in Harness:

- **Organisation**: `business_unit_one`
- **Project**: `ecs_project`
- **Connectors**: `ecs_connector` (project-scoped, ECR access) and `org.ecs_git_connector` (org-scoped, GitHub access to this repo)
- **AWS Connector**: `org.ecs_aws_connector` (org-scoped, used by triggers for ECR polling)
- **Infrastructure Definitions**: `ECS_Dev` and `ECS_Prod` (ECS cluster + Fargate config per environment)
- **User Group**: `org.Release_Managers` (approvers for production promotion)
- **Secret**: `slack_webhook_url` (Slack notification webhook)
- **Project Variable**: `ecr_registry_id` (AWS account ID owning the ECR registry)
- **Environment Overrides**: Global Environment overrides for Dev and Prod with networking, IAM roles, and ECR account ID

## Sample Applications

The `app-example/` folder contains two Spring Boot applications for testing:

| App | Package | Endpoint | Health Check |
|---|---|---|---|
| app1 | `com.example.greeting` | `GET /api/greeting?name=World` | `/actuator/health` |
| app2 | `com.example.inventory` | `GET /api/inventory` | `/actuator/health` |

Build and push to ECR:
```bash
cd app-example/app1
docker build -t <account-id>.dkr.ecr.eu-west-2.amazonaws.com/app1:1 .
docker push <account-id>.dkr.ecr.eu-west-2.amazonaws.com/app1:1
# Trigger fires automatically
```

## Documentation

- **[CLAUDE.md](CLAUDE.md)** -- Architecture principles, variable tier rules, known gaps, and development conventions
- **[Harness-ECS-Landing-Zone-Guide.docx](Harness-ECS-Landing-Zone-Guide.docx)** -- Customer-facing architecture guide (Word format)

## References

- [Harness ECS Deployments](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/aws/ecs/)
- [Harness Service Concepts](https://developer.harness.io/docs/continuous-delivery/get-started/key-concepts/)
- [Harness Overrides V2](https://developer.harness.io/docs/continuous-delivery/x-platform-cd-features/overrides-v2/)
- [Harness Git Experience](https://developer.harness.io/docs/platform/git-experience/)
- [Harness Triggers](https://developer.harness.io/docs/platform/triggers/)
