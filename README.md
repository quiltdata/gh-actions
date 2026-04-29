# gh-actions

Reusable GitHub Actions and composite actions for quiltdata repos.

## Actions

### [deploy-ecr](./deploy-ecr)

Unified ECR image action. Builds a Docker image from the caller's checked-out
workspace, pushes it to a configurable subset of ECR targets, and optionally
forces ECS Fargate deployments for deployable targets.

Targets:

- `prod` — account 730278974607, us-east-1
- `mp` — Marketplace account 709825985650, us-east-1, push-only
- `govcloud` — account 313325871032, us-gov-east-1

`push_targets: '[]'` builds only. Empty `image_tag` resolves to
`git rev-parse HEAD`, which keeps image tags correct when a dispatch workflow
checks out a different branch than the dispatching ref.

```yaml
- uses: actions/checkout@v6
  with:
    ref: ${{ inputs.ref || github.ref }}
- uses: quiltdata/gh-actions/deploy-ecr@main
  with:
    image_name: quiltdata/catalog
    push_targets: ${{ inputs.push_targets || '["prod","mp","govcloud"]' }}
    mp_image_name: quilt-data/quilt-payg-catalog
    role_name: Quilt
```

For ECS services, pass `cluster_name` and `service_name`; deployments run for
pushed `prod` and `govcloud` targets only.

```yaml
- uses: quiltdata/gh-actions/deploy-ecr@main
  with:
    image_name: quiltdata/services/foo
    cluster_name: my-cluster
    service_name: my-service
    push_targets: ${{ inputs.push_targets || '["prod","govcloud"]' }}
```

For Lambda-style image fanout, set `multi_region: 'true'` to push to every
enabled region in each selected target account.

### [build-and-push-ecr](./build-and-push-ecr)

Build a Docker image and push to a configurable subset of ECR targets:
`prod` (account 730278974607, us-east-1), `mp` (Marketplace, cross-account
709825985650), `govcloud` (account 313325871032, us-gov-east-1).

Legacy split action. Prefer `deploy-ecr` for new workflows.

`push-targets: '[]'` builds only — useful for dev iteration via
`workflow_dispatch` without polluting any ECR.

```yaml
- uses: actions/checkout@v6
- uses: quiltdata/gh-actions/build-and-push-ecr@main
  with:
    image-name: quiltdata/catalog
    push-targets: ${{ inputs.push-targets || '["prod","govcloud","mp"]' }}
    mp-image-name: quilt-data/quilt-payg-catalog
    role-name: Quilt
```

### [fargate-deploy-ecr](./fargate-deploy-ecr)

Same build + push flow, plus `aws ecs update-service --force-new-deployment`
per target for ECS Fargate services. Targets: `prod`, `govcloud` (no MP —
Marketplace is a distribution registry, not a deploy target).

Legacy split action. Prefer `deploy-ecr` for new workflows.

```yaml
- uses: actions/checkout@v6
- uses: quiltdata/gh-actions/fargate-deploy-ecr@main
  with:
    image-name: quiltdata/services/foo
    cluster-name: my-cluster
    service-name: my-service
    push-targets: ${{ inputs.push-targets || '["prod","govcloud"]' }}
```

### [lambda-deploy-ecr](./lambda-deploy-ecr)

Legacy lambda image build + push. Pushes to all enabled regions per account
(needed because Lambda functions are region-scoped). Kept for back-compat;
new lambda workflows can use `deploy-ecr` with `multi_region: 'true'`.

### [lambda-upload-s3](./lambda-upload-s3)

Build a lambda zip via the lambda builder image and upload to S3.

## Conventions

- All ECR-pushing actions assume the consumer repo has an IAM role at
  `arn:aws:iam::<account>:role/github/GitHub-<role-name>` (and the GovCloud
  equivalent), where `<role-name>` defaults to the repo name and can be
  overridden via the `role-name` input.
- The `push_targets` JSON-array pattern — default `["prod","govcloud"]` for
  push events, `["prod"]` or `[]` for `workflow_dispatch` — is the org
  convention for letting `workflow_dispatch` produce dev images without
  pushing to release-channel registries (Marketplace, GovCloud).
- Callers are responsible for `actions/checkout` before calling
  `deploy-ecr` (so a pre-build step like `npm run build` can populate the
  workspace first). The legacy `lambda-deploy-ecr` does its own checkout.
