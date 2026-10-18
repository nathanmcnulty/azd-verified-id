# Backlog: nathanmcnulty/azd-verified-id

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-verified-id
- **Source revision:** `7f98a37b025094de6ebf5cb15f11552aa7a5dbd9`
- **Captured:** 2026-10-04
- **Items:** 7

## VID-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- https&colon;//github.com/nathanmcnulty/azd-verified-id/pull/9
- https&colon;//github.com/nathanmcnulty/azd-verified-id/pull/10

**Evidence:**

- Reconciled against current main 7f98a37b025094de6ebf5cb15f11552aa7a5dbd9 in a clean worktree. Issues &num;6, &num;7 and &num;8 are closed by merged PRs &num;9 and &num;10; no issue or pull request remains open. The canonical permission-tracking checkout and its .azure directory were preserved without reading values; no .env path was present.
- Current-base scripts/Test-Repository.ps1 passed PowerShell syntax, Bicep and 42/42 Pester tests. No token acquisition, bootstrap write, uploader execution, DNS change, issuance or presentation operation ran.

**Review and authorization note:**

Review VID-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-004: Pin reviewed static site uploader binary version and integrity

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-verified-id/issues/8
- https&colon;//github.com/nathanmcnulty/azd-verified-id/pull/10

**Evidence:**

- Issue &num;8 is fixed by merged PR &num;10 at current main&colon; StaticSitesClient.lock.json records immutable platform URLs and SHA-256 values, StaticWebApp.psm1 validates lock shape and cached/downloaded bytes, and StaticSitesClient.Tests.ps1 covers failure cases. The PR reports full syntax, analysis, Bicep and 42 Pester tests plus a matching Windows download; publisher authentication, execution and deployment remain unproven.

**Review and authorization note:**

Review VID-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-005: Bind acquired Graph tokens to the selected tenant before bootstrap writes

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-verified-id/issues/7
- https&colon;//github.com/nathanmcnulty/azd-verified-id/pull/9

**Evidence:**

- Issue &num;7 is fixed by merged PR &num;9 at cb95bd573df84da804b73808a08b292131f5739d&colon; GraphBootstrap.psm1 validates token tenant and delegated identity before Graph writes, with BootstrapSafety.Tests.ps1 covering the boundary. The PR reports 38 Pester tests and Bicep validation; no live bootstrap write is claimed.

**Review and authorization note:**

Review VID-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-006: Infrastructure-only bootstrap can perform orphan cleanup before tenant validation

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-verified-id/issues/6
- https&colon;//github.com/nathanmcnulty/azd-verified-id/pull/9

**Evidence:**

- Issue &num;6 is fixed by merged PR &num;9&colon; infrastructure-only preprovision avoids unnecessary Graph scope/bootstrap cleanup, recorded applications are not deleted implicitly, and Remove-OrphanedAdminApplication.ps1 provides an explicit tenant-bound recovery path. The PR reports 38 Pester tests and Bicep validation; no orphan cleanup or tenant mutation ran.

**Review and authorization note:**

Review VID-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-007: Require the supported authoring and validation baseline

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Owned bootstrap entrypoints lacked a PowerShell floor; the validator allowed old or absent Pester, while inconclusive, skipped or empty suites could appear successful.

**Scope:**

- Owned scripts and modules runtime declarations
- scripts/Test-Repository.ps1 and .github/workflows/validate.yml
- Current README prerequisites and canonical backlog evidence

**Acceptance:**

- Owned authoring entrypoints require PowerShell 7.6+; CI selects verified PowerShell 7.6.6 and Pester 6.2.0.
- Missing Pester and empty, failed, skipped, inconclusive or unexecuted suites fail validation.
- Retain every existing safety assertion, permission requirement, deployment default and integrity-locked uploader byte.

**Validation:**

- ./scripts/Test-Repository.ps1
- Check canonical backlog schema and regenerate docs/backlog.md.
- Run actual validator copies against isolated passing, inconclusive, mixed-skipped, all-skipped, empty, failing and missing-Pester fixtures; compare old and corrected results.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-verified-id/issues/13

**Evidence:**

- Reconciled exact current main a3c368e605852f30a66d82304b51907bb037ea67 before editing; no active draft overlaps this task. All 14 owned script/module files declare PowerShell 7.6 &lpar;12 newly added guards&rpar;. Current requirements use PowerShell 7.6+ and exact Pester 6.2.0 validation; historical receipts remain unchanged.
- Full scripts/Test-Repository.ps1 passes on PowerShell 7.6.6/.NET 10.0.12/Pester 6.2.0&colon; syntax, existing Error-severity static analysis, Bicep 0.42.1 and 86/86 tests with zero failures, skips, inconclusive or unexecuted cases. No test or safety assertion was removed or weakened. Permission semantics, uploader lock/assets, infrastructure and application behavior remain unchanged. No authentication, deployment, DNS change, issuance, presentation or cleanup ran; VID-002 native acceptance remains open.
- Actual original/current validator copies ran in 14 isolated PowerShell 7.6.6 processes against passing, inconclusive, mixed-skipped, all-skipped, empty, failing and missing-Pester fixtures. The original accepted every case except failure; the corrected validator accepts only the passing case. Missing Pester now stops before Bicep. Native-command tripwires permitted only the controlled Bicep invocation; no authentication or cloud calls occurred.

**Review and authorization note:**

Review VID-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-002: Qualify DNS/domain verification, issuance and presentation

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Authority and credential configuration do not establish usable user credentials or verified presentation.

**Scope:**

- docs/
- scripts/
- infra/

**Acceptance:**

- Record exact owned domain/authority and DNS propagation, credential issuance and real presentation results.
- Test interrupted propagation, retry and resume without duplicating authority or changing signing material.
- Verify safe owned-object removal while preserving shared domains and unrelated tenant configuration.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md

**Evidence:**

- _none_

**Review and authorization note:**

Review VID-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## VID-003: Add resumable read-only setup status and permission deltas

- **Kind:** feature
- **Priority:** P2
- **Status:** done
- **Wave:** 2
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Operators need clear pending DNS, authority, credential and delivery status without exposing signing secrets.

**Scope:**

- scripts/
- docs/
- azd-components.lock.json
- azd-permissions.json

**Acceptance:**

- Report each external setup gate separately and preserve actionable pending states.
- Evaluate deployment-validation and candidate receipt reuse; key material and request secrets remain outside receipts.
- Define read-only resume versus authorized DNS/tenant/signing writes and record exact permissions.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- deployment-validation
- deployment-receipt

**Sources:**

- README.md

**Evidence:**

- Implemented standalone read-only PS7.6+ status entry point against main 4d34f9a1c87c948190bd188fd2aa97d7ca58798b. Eleven independent actionable gates, fresh GET observations, exact tenant/operator/admin-audience/scope/expiry routing guard, selected authority/vault/contract binding, no bootstrap imports, token acquisition, secret routes, writes or stored Complete reuse. Unsigned decoded public/admin claims remain Observed; fresh service domain flags are required for configuration readiness. Independent review found that a returned foreign contract authorityId was ignored; repaired both list/exact paths to reject present empty/null/foreign bindings while supporting documented omission. Negative fixtures prove no downstream MyAccount GET.
- Full registered scripts/Test-Repository.ps1 passed syntax, analyzer, Bicep 0.46.1 and 86/86 Pester tests &lpar;43 new actual status/transport/CLI fixtures and one new canonical permission-schema/source-hash test&rpar;. No live DNS, admin authorization, service verification, issuance, presentation or cleanup was performed; VID-002 remains open.
- docs/read-only-setup-status.md evaluates deployment-validation 1.1.1 and candidate deployment-receipt 0.2.1 at immutable reference 277584b33fcae7d47113718aad6428abdc4bc50f&colon; both deferred, no adoption/lock/runtime dependency. Source-hashed partial azd-permissions.json records existing admin full&lowbar;access and Graph bootstrap requirements with explicit target-role/RBAC/signing/DNS gaps; no grants or permission changes.

**Review and authorization note:**

Review VID-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
