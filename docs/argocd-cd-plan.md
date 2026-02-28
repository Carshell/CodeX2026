# Argo CD Implementation Plan (CD)

## 1. Scope and decisions

1. Use Argo CD for deployment only; keep CircleCI for test/build/push.
2. Use Kustomize overlays as the deployment source of truth.
3. Start with `dev` and `staging`, then add `prod` after promotion flow is stable.
4. Deploy core services first; include optional components (`shopping-assistant`, `alloydb`, `spanner`, etc.) only per environment needs.

## 2. Repository layout to add

1. Create `deploy/overlays/dev`, `deploy/overlays/staging`, `deploy/overlays/prod`.
2. Each overlay should reference `kustomize/base` and required components.
3. Add image overrides in each overlay for registry/tag (or digest).
4. Add `deploy/argocd/project.yaml` and one `Application` manifest per environment.

## 3. Bootstrap Argo CD

1. Install Argo CD in a dedicated cluster namespace (`argocd`).
2. Enable SSO/RBAC groups for platform and service owners.
3. Configure repository credentials (HTTPS token or SSH key).
4. Create one `AppProject` with:
   - allowed source repos
   - allowed destinations (cluster/namespaces)
   - restricted cluster-scoped resources

## 4. Create Argo CD applications

1. Define `online-boutique-dev` app pointing to `deploy/overlays/dev`.
2. Define `online-boutique-staging` app pointing to `deploy/overlays/staging`.
3. Enable automated sync + self-heal in `dev`.
4. Keep `staging` manual sync initially, then switch to automated after validation.
5. Add sync waves/hooks only if ordering issues appear.

## 5. Integrate CI with GitOps promotion

1. CircleCI builds and pushes images tagged with commit SHA.
2. CircleCI updates overlay image tag/digest in Git (no `kubectl apply` in CI).
3. CircleCI opens a PR to promote:
   - `dev` update auto-created from main
   - `staging`/`prod` updates through approval PRs
4. Argo CD detects merged manifest changes and performs sync.

## 6. Secrets and config management

1. Do not commit plaintext secrets to Git.
2. Choose one method: External Secrets Operator, Sealed Secrets, or SOPS + age/KMS.
3. Store environment-specific non-secret config in overlay `configMapGenerator` or plain manifests.
4. Add secret rotation runbook and ownership.

## 7. Observability and guardrails

1. Enable Argo CD notifications (Slack/email) for sync success/failure.
2. Monitor drift, health status, and sync duration.
3. Add policy checks before merge (kustomize build, kubeconform/kubevious, optional OPA/Kyverno checks).
4. Define rollback process: revert overlay commit and sync.

## 8. Migration phases

1. Phase 1: bootstrap Argo CD + deploy `dev` only.
2. Phase 2: route current staging deployment through Argo CD.
3. Phase 3: production cutover with manual approval gate.
4. Phase 4: remove imperative CD steps from old pipelines.

## 9. Definition of done

1. Deployments are triggered only by Git changes in deployment manifests.
2. Argo CD shows healthy/synced state for all target environments.
3. Drift is auto-corrected (or blocked with clear alerting).
4. Promotion between environments is PR-based and auditable.
