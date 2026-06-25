# Chattea Infra Plan

## Summary
- AWS 인프라, secrets, observability 연동, 배포 기반.
- 담당:
  - infra resources
  - secrets wiring
  - network/security boundaries
  - runtime env config

## Environments
- `dev`
- `prod`

## Core AWS
- VPC.
- public/private subnets.
- security groups.
- ECS/Fargate or App Runner for BE.
- RDS PostgreSQL.
- ElastiCache Redis.
- S3 attachments bucket.
- CloudFront optional for attachments.
- Secrets Manager or SSM Parameter Store.
- CloudWatch logs.

## Backend Deploy
- container image registry via ECR.
- service env vars from Secrets Manager/SSM.
- health check endpoint.
- autoscaling minimal config.

## Realtime
- ALB/WebSocket-compatible routing if ECS.
- sticky session avoided; Redis pub/sub handles fanout.

## Phone Verification Infra
- SMS provider: AWS SNS v1.
- BE task role에 SNS publish 최소 권한.
- env/secret:
  - `AWS_REGION`
  - `SMS_SENDER_ID` 또는 AWS SNS에서 지원되는 발신 속성
  - `PHONE_CODE_PEPPER`
- `PHONE_CODE_PEPPER`는 secret output 금지.
- CloudWatch/Sentry/Datadog 로그에서 `phone`, `code`, `signupToken`, `session` redaction 전제.
- AWS SNS 한국 SMS 발신번호/템플릿 제약은 prod 전 확인 필요.

## Security
- RDS private subnet only.
- Redis private subnet only.
- S3 bucket private.
- presigned upload only.
- IAM least privilege per service.
- Secret values must not be Terraform outputs.

## Observability
- Datadog agent/forwarder setup.
- Sentry DSN as secret.
- app env tags:
  - `service`
  - `env`
  - `version`

## Tests
- `terraform fmt -check`.
- `terraform validate`.
- `terraform plan`.
- policy/security review for public exposure, SG rules, secret outputs.
- IAM review: SNS publish scoped, no secret outputs.
