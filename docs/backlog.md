# Backlog: nathanmcnulty/azd-verified-id

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-verified-id
- **Source revision:** `7f98a37b025094de6ebf5cb15f11552aa7a5dbd9`
- **Captured:** 2026-10-04
- **Items:** 6

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
- **Status:** proposed
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

- _none_

**Review and authorization note:**

Review VID-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
