# Verification Reference

REQUIRED while classifying findings. Use this to decide whether a finding is a real bug, false positive, coverage gap, deferred item, or UI/browser issue.

## Phase 2: Classify

For each comment, determine:

**A. Is it a real issue?** Verify against code — does the code actually have this bug?

**B. Severity**

| Level | Criteria | Action |
|-------|----------|--------|
| P1 | Real bug, affects functionality/data | Verify, then fix or dismiss |
| P2 | Risky but non-blocking | Verify, handle as appropriate |
| Style (introduced by this PR) | Convention/style issue from this change | Fix and resolve |
| Style (pre-existing) | Convention/style issue from older code | Resolve directly, leave for a dedicated PR |

## Phase 3: Verify

**For each P1/P2 comment, verify one by one:**

### 3a0. Check shared-component and shared-file blast radius

Review comments often point at one call site while the real contract lives in a
shared component, hook, or script. Before deciding the verdict, check whether
the touched code is shared.

**Shared UI/component state contract check:**

1. If the comment touches a reusable component, hook, modal, tab container, or
   state holder, run `rg` for all call sites before changing behavior.
2. Record the affected entry points in the Evidence & Ownership table, including the
   originally reported path and at least one existing user path if present.
3. For state-like props (`defaultXxx`, `activeXxx`, `value`, `onXxxChange`,
   `onChange`), identify the contract explicitly:
   - `defaultXxx` initializes internal state only.
   - `activeXxx` / `value` controls state from the parent.
   - `onXxxChange` / `onChange` reports user interaction.
4. If a reviewer asks for controlled behavior, preserve existing uncontrolled
   interaction unless the product request explicitly removes it.
5. The test plan must include both the review-comment path and the existing
   interaction path, so a fix for one call site cannot regress another.

**Shared script/file maintenance check:**

1. If the comment touches CI helpers, generated files, managed blocks, scripts,
   or files with headers such as "shared with ...", read the file header and
   nearby docs before editing.
2. Determine whether the change is shared behavior or repo-specific config.
3. For shared behavior, sync the consumer repo/file in the same task when it is
   available; otherwise record the explicit non-sync reason in the Evidence &
   Ownership table and TODO.
4. Verify both the source repo and the synced consumer repo, or report which
   side could not be verified and why.

**Skill ownership boundary:** keep these local workflow rules here and in the
repo's `AGENTS.md`. Do not edit the upstream
`dot-agents/skills/superpowers/receiving-code-review/SKILL.md`, because it is
owned upstream and may be overwritten by upgrades.

### 3a0.5 Abstraction-level and generator gate

Review comments often identify a symptom at one changed file, not the correct
ownership layer. Before proposing any fix, decide where the behavior belongs.
Do not implement a repeated call-site patch until this gate is answered.

Required checks:

1. Identify the smallest owner that can enforce the contract for all current
   and future callers:
   - request/response layer for transport-wide response semantics
   - shared component/hook for reusable UI behavior
   - domain helper for one business domain shared by several pages
   - page component only for genuinely page-specific behavior
2. If the same wrapper, guard, toast, payload mapping, or conditional would be
   needed in more than one page/call site, treat the page-level fix as a smell.
   Prefer the shared owner unless concrete evidence shows the behavior differs
   by page.
3. Check whether generated code, templates, scaffolding scripts, managed blocks,
   or copied reference implementations can create the same bug again.
4. If a template/scaffold already produces the correct shape, add or update a
   generator/template regression test that locks the contract. If it produces
   the wrong shape, fix the template and add the regression test.
5. Put regression tests at the same abstraction layer as the fix. Shared
   behavior needs shared-component/helper/script tests; page tests should only
   cover page-specific contracts or representative integration paths.
6. Cross-check `Fix Strategy` against the Regression Plan. Every shared owner,
   lower-level helper, public wrapper, script, generated template, or API
   surface named in `Fix Strategy` must have its own `RP-*` coverage group. If
   the plan says "change request wrapper", "change shared hook", "change
   generator", or similar, a caller-only regression plan is incomplete.
7. Build an Owner/RP Coverage Matrix by mechanically extracting every noun phrase
   in `Fix Strategy` that refers to a changed module, helper, wrapper, public
   API, generated template, or caller. Mark each one `covered` or `missing`.
   Any `missing` row is a stop sign before approval.
8. For public helper/API surface changes, the `RP-*` group must cover:
   - existing default behavior and positional-argument compatibility;
   - new behavior introduced by the fix;
   - side effects on shared/global state;
   - all sibling wrappers touched by the abstraction, or explicit `N/A` rows
     explaining why they are not touched;
   - at least one representative caller for each adapted call path.
9. If any public helper has broad call volume or ambiguous overloads, inspect
   call sites before approval and record the compatibility risk in
   Evidence & Ownership. Do not rely only on the reviewed call site.
10. If the fix changes a shared/lower-level owner, plan three independent fresh
   reviews of the Owner/RP Coverage Matrix and Regression Plan before approval.
   Do not proceed until all three report zero missing owner regression coverage.

The Evidence & Ownership table for every code-change item must include:

- `Abstraction owner`: chosen layer and why lower layers were not used
- `Repeated patch check`: whether the proposed change would otherwise be
  duplicated across call sites
- `Generator/template impact`: changed, covered by regression test, or N/A
- `Test level`: where RED and regression coverage live, matching the owner

### 3a. Read code to confirm whether the issue exists

```bash
# Read the lines the comment points to
sed -n '{line-5},{line+10}p' {path}
```

The issue may already be fixed (comment was from an earlier revision). If so, mark as "already fixed".

### 3b. Check API docs to confirm bot assumptions

Bots often guess behavior based on other modules. Always verify against API docs:

```
# Use VShield API MCP or read the OAS directly
mcp__VShield_API_____read_project_oas_ref_resources
```

### 3b.2 Check installed third-party contracts before accepting API claims

When a review finding depends on third-party library behavior, version-specific
API names, hook return fields, component props, or deprecation status, verify
the **locally installed contract** before deciding the verdict.

Required checks:

1. Read the exact installed version from `node_modules`, the lockfile, or the
   package manager metadata; do not rely only on broad ranges such as `"4"`.
2. Inspect the installed `.d.ts` and, when the claim is about runtime behavior,
   the installed runtime source/build output.
3. If the reviewer claims an API is unavailable or wrong but the local installed
   contract shows it is available and supported, classify the finding as
   **False positive** unless another concrete bug remains.
4. Record the installed version and the checked file/path in the decision-table
   notes. For example: `@tanstack/react-query@4.43.0` exposes `isPending` as
   the mutation loading alias while `isLoading` is deprecated.

### 3b.5 False-positive guard and coverage check

Before marking any finding as "Real bug", confirm it with concrete evidence.
Do not rely on the reviewer comment plus a plausible reading of the code.

Required evidence for a "Real bug" verdict:

1. The reported path is reachable in the current code.
2. The current behavior violates an API contract, product requirement, existing
   pattern, or clearly intended invariant.
3. A targeted test can demonstrate the behavior, or an existing test already
   covers the same contract and would fail if the bug exists.

If the code looks suspicious but there is no test coverage for the contract,
classify the next action as **coverage-first verification** in the decision
table. After user approval, add the smallest targeted test first:

- If the test fails, the finding is confirmed as a real bug; continue with the
  TDD fix cycle.
- If the test passes, stop and reclassify the finding as false positive,
  already fixed, or coverage-only. Do not change production code.
- If the behavior is correct but important enough to lock down, add a
  test-only coverage commit and reply that the finding was not a bug but the
  contract is now covered.

Never turn a coverage gap into a production fix without first proving the bug
with a failing test.

### 3b.5.1 Regression coverage planning

For every item that may change code, decide whether the minimal RED test is
enough or whether additional regression tests are required.

Required checks:

1. Identify the affected contract: API payload, UI state, authorization,
   lifecycle, shared component props, migration behavior, or script output.
2. List adjacent modes and entry points that should remain unchanged. Examples:
   manual vs automatic source, normal vs temporary flow, old enum values vs new
   enum values, existing callers of a shared component, and existing CLI flags.
3. Add regression tests when the fix touches shared code, branches by mode,
   normalizes/clears data, changes defaults, or has a known previous behavior
   that must be preserved.
4. Assess the current regression coverage of the code touched by the review
   item before choosing the test plan. Use the most precise available signal:
   targeted test coverage, file coverage, branch/changed-line coverage, or
   explicit contract tests when line coverage is unavailable.
5. Plan coverage to keep the affected path at **95% or higher**. For critical
   paths, plan **100% coverage of the decision branches involved in the review
   finding**, including failure/empty/cleared states when relevant. Critical
   paths include data loss, authorization, submit payload construction,
   destructive actions, visible navigation, uploads, and async click/submit
   gates.
6. If the existing coverage is below the target, add regression tests or a
   coverage-only proof step before changing production code. If the target is
   impractical or not measurable with local tooling, record the reason and the
   substitute evidence in the Regression Plan table; do not silently skip it.
7. When adjacent behavior is user-visible, regression coverage must include
   browser/page verification unless the Regression Plan table records why
   component or unit coverage is sufficient.
8. If no additional regression test is needed, record the reason in the
   Regression Plan table, for example: `Regression Action=N/A`, reason
   `single pure helper with exhaustive RED assertion`.

The decision package must name the TDD work in the dedicated Regression Plan
and TDD / Commit / Reply Plan tables:

- `RED`: the failing test that reproduces the review finding.
- `Existing GREEN`: already-covered behavior plus baseline command/result.
- `Add old-GREEN`: currently correct but uncovered/weak behavior that must be
  proven before the review-finding RED or production code edit.
- `Post-fix GREEN`: behavior only provable after the implementation change.
- `Coverage target`: existing coverage signal, planned target (95%+, or 100%
  for critical paths), and the exact test/coverage command that will prove it.
- `Browser Regression`: the route/user path and Browser GREEN evidence when
  needed, or `N/A` with a reason when browser coverage is not needed.

Keep the Decision Table narrow; it should reference `RP-*`, `EO-*`, and `TDD-*`
rows rather than embedding thread/source ids, long paths, baselines, or review
comment translations. Put path, source id, evidence, owner, blast radius,
baseline quality, closeout level, and original/translated review text in the
Evidence & Ownership table.

### 3b.5.2 Form field path vs payload path

When a review finding says a form field should match an API payload path, such
as changing `field="isActive"` to `field="filter.isActive"`, treat it as a
contract-boundary claim, not a string rename.

Required checks:

1. Identify whether a hook, adapter, submit handler, payload builder, or list
   abstraction maps form values into the final API payload.
2. Verify the contract of that layer before accepting the reviewer's proposed
   field path.
3. The RED test must assert the final submitted/search payload shape or atom
   state, not merely that a JSX `field` string was rendered.
4. If the current code has only a field-string assertion, replace it with a
   user-submission or payload-shape regression before changing production code.
5. For user-visible filters, include browser request-body evidence when the
   route can be exercised safely.

### 3b.6 Prove async UI races at the user-action boundary

When a finding claims an async timing bug in UI code, such as `useEffect`
fire-and-forget promises, session renewal, upload readiness, render timing,
loading gates, or a brief window where the user can click before async work
finishes, static code is not enough to mark it as a real bug.

Required checks:

1. Split the finding into separate claims:
   - static fact (for example, a promise is not awaited)
   - reachable user action (for example, the upload button is enabled before
     renewal finishes)
   - user impact (for example, the upload reads stale auth and receives `401`)
2. Static code may prove the static fact only. It does **not** prove reachable
   user impact.
3. Before verdict **Real bug**, prove the user-action boundary with a controlled
   async test or browser/page verification:
   - hold the relevant promise pending
   - reach the page state under review
   - assert whether the user-visible action is available before the promise
     settles
4. If the static fact is suspicious but the user-action boundary is unproved,
   classify the item as **Needs proof / coverage-first verification** in the
   decision package. Only after the proof test fails may production code be
   changed.

### 3b.7 Browser verification for UI findings

For UI review findings, also apply `wf-ui-browser-verification`. Treat that
skill as the source of truth for user-boundary verification, browser control
tool selection, and auth strategy. This section adds PR-triage-specific gates
and reporting requirements. Do not duplicate the browser workflow here; update
`wf-ui-browser-verification` when the shared browser rules change.

When a finding is about visible page state, form defaults, disabled/enabled
buttons, navigation, toast behavior, uploads, loading/error/empty states, or any
claim that "the user can see/click/submit/reach X", Phase 3 must include
browser/page verification unless the item is classified as Needs proof and no
verdict is being made yet. Execute the verification using
`wf-ui-browser-verification`, then record the PR-triage evidence below.
Do not replace this with source inspection or unit tests alone unless the
decision package explicitly proves that the reviewed behavior is not visible at a
user-action boundary.

Record in the Evidence & Ownership or Regression Plan table:

- `Browser path`: route and user steps
- `Browser control`: in-app browser, user-profile browser, or scripted /
  protocol-driven automation, including the concrete tool when known
- `Auth method`: real login, injected auth, or mocked auth/backend; mention the
  project auth-state helper when used
- `Evidence`: what was visible/clickable/disabled/selected
- `Limitations`: anything not covered, such as mocked backend responses

### 3c. Compare reviewer's solution against your own (MANDATORY)

When a review comment proposes a concrete alternative implementation (e.g., "use `Get-NetTCPConnection` instead of `findstr`"), and you decide on a different fix, you MUST:

1. List both approaches in the Decision Table `Fix Strategy` cell when short,
   or in the Evidence & Ownership table when pros/cons need more room
2. Justify why your approach is better with concrete evidence — **OR** adopt the reviewer's approach
3. Never silently dismiss the reviewer's suggestion in favor of your own

If unsure which approach is better, present both to the user and let them decide.

### 3d. Determine verdict

| Verdict | Action |
|---------|--------|
| Real bug | **TDD fix**: RED test → GREEN fix → reply (✅ commit hash + test name), resolve |
| False positive | Reply (ℹ️ cite code/API docs as evidence), resolve |
| Already fixed | Reply (✅ confirm fix + commit hash), resolve |
| Coverage gap only | Add targeted test-only coverage if useful, reply (ℹ️ not a bug + test evidence), resolve |
| Deferred (TODO) | Create `docs/todo/` entry, reply (📋 link + reason), resolve |
| Style issue | **TDD fix**: RED test → GREEN fix → reply (✅ fixed + test name), resolve |

**Deferred 必须记入 `docs/todo/`**（见下方 "Deferred → TODO 文件"）。

### Reply format

Every resolve MUST be preceded by a reply explaining the verdict. This gives reviewers (bot or human) transparency into the decision.

**Fixed:**
> ✅ Fixed in `{hash}`: `{file}` line N — {specific change}. TDD: RED `{test_name}` → GREEN.

**False positive:**
> ℹ️ Not an issue — {evidence}. (e.g., "backend validates at line N", "GORM naturally skips zero values")

**Already fixed:**
> ✅ Already fixed in `{hash}`. Current code: {specific state}.

**Deferred (TODO):**
> 📋 Recorded as `docs/todo/{slug}.md` — {reason for deferral}. (e.g., "needs architecture change")

### Deferred → TODO 文件

每个 Deferred 项必须在 `docs/todo/` 创建对应文件：

```yaml
---
priority: low | medium | high
area: 对应模块（如 contractor, components, infrastructure）
source: PR #{number} review — {日期} {bot/人}
refs:
  - designs/xxx.md    # 或 plans/xxx.md 或 prds/xxx.md（至少一个）
---

# {标题}

{简要描述问题、为何暂缓、建议方案}
```

文件命名：`{简短-slug}.md`。创建后在 reply 和 decision package 中用相对路径引用（如 `docs/todo/audit-component-directory.md`）。
