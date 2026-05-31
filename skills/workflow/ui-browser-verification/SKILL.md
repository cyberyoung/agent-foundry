---
name: wf-ui-browser-verification
description: Use when implementing, testing, reviewing, or triaging user-facing UI behavior that depends on visible page state, auth-gated flows, forms, navigation, uploads, loading states, or async interaction timing.
---

# UI Browser Verification

## Overview

Browser verification proves what a user can actually see or do. Use it for UI
behavior that source reading, unit tests, or type checks cannot fully establish.

## When Browser Verification Is Required

Use browser/page verification for claims about:

- visible or hidden page state
- form defaults, selected values, and validation messages
- enabled or disabled controls
- toasts, navigation, redirects, and route guards
- uploads, signatures, file pickers, and submit buttons
- loading, error, empty, and permission states
- `useEffect`, timers, promises, retries, renewals, or race windows

Do not require browser verification for pure utility functions, type-only
changes, API payload formatting already covered by tests, or non-UI CI scripts.

## User Boundary Check

Verify the user-action boundary, not just source code or static DOM:

1. Navigate to the route or reproduce the user path.
2. Wait for the real loading state or mocked fixture state to settle.
3. Check the user-visible state that proves the claim: text, selected value,
   disabled state, button availability, toast, URL, modal, or upload action.
4. For race claims, hold the relevant promise pending, reach the page state,
   and verify whether the user-visible action is available before it settles.
5. If the boundary is not proven, classify the item as Needs proof instead of
   Real bug.

## Hard Completion Gate

For changes that affect user-visible UI behavior, browser evidence is a
completion requirement. Do not mark the work complete, create a final commit, or
request merge until the browser boundary has been verified, unless the user
explicitly waives browser verification for that task.

The following are not valid reasons to skip browser verification:

- the in-app browser cannot type into the form
- login is inconvenient or blocked in the first browser tool
- the local backend lacks realistic data
- the form has many required fields
- unit tests, component tests, source inspection, or type checks passed

If the first browser tool cannot prove the boundary, continue with another
least-risk path before reporting a blocker:

1. inject project-provided local auth state
2. use a same-origin temporary page or browser console to write auth state
3. mock or intercept backend requests with stable fixtures
4. use Playwright, Chrome, CDP, or another scripted browser tool
5. use a stable test account for real login when real permissions are required

Only stop before these alternatives when they would require sensitive accounts,
production data, destructive actions, real uploads, password-change final
submits, or other user-confirmed sensitive operations.

## Browser RED/GREEN For Fixes

When browser verification is part of a bugfix or PR-review TDD cycle, collect it
on both sides of the code change:

- **Browser RED**: before editing production code, reproduce the reported user
  path and record the visible failure at the browser boundary. Examples:
  missing text, clipped layout, enabled button during pending work, wrong route,
  duplicate toast, focus escaping the dialog, or an upload action available
  before initialization finishes.
- **Browser GREEN**: after the minimal fix and automated tests pass, repeat the
  same route and user action, then record the visible state that now satisfies
  the contract.
- Browser RED/GREEN does not replace the targeted automated failing test unless
  the user explicitly approves a substitute evidence standard. It complements
  the test by proving that the bug and fix are real in the user-visible surface.
- If Browser RED is impractical because of unavailable auth, unsafe production
  data, non-deterministic external systems, or missing local infrastructure,
  stop and report the limitation before changing production code.

## Tool Selection

Select the browser control method by the evidence needed. If the user names a
specific tool, connector, or browser, use that unless it cannot prove the
required boundary.

- In-app browser control: use for local `localhost` pages, the current in-app
  browser tab, fast manual reproduction, and visible UI checks that do not need
  the user's real browser profile.
- User-profile browser control: use when the check depends on existing cookies,
  real logged-in sessions, browser extensions, remote authenticated pages, or
  the user's current browser state.
- Scripted or protocol-driven browser automation: use for repeatable local or
  CI checks, assertions, screenshots, traces, network inspection, console
  capture, performance data, or deep browser instrumentation. Prefer the
  project's existing automation tool; examples include Playwright, Cypress,
  WebdriverIO, Puppeteer, CDP-based tools, and Vitest Browser Mode.

Auth-state helpers should generate app-specific auth state only. The selected
browser control method is responsible for injecting that state, navigating, and
collecting evidence.

## Auth Strategy

Pick the least risky auth method that proves the behavior:

- Real login: use a stable local/test account when the task needs real
  permissions, route guards, or backend integration.
- Injected auth: for UI-only checks behind login, write the same local auth
  state the app expects, including token, token type, user state, scene markers,
  refresh token, and expiry.
- Mocked backend: for UI state or race checks, intercept requests with stable
  fixtures when real backend data is irrelevant.
- Sensitive actions: ask the user before using real sensitive accounts,
  passwords, one-time codes, production data, uploads, deletes, account changes,
  or password-change final submits.

If the auth library validates token expiry, use a local test token with a future
expiry. Do not use real production tokens as fixtures.

## Evidence Format

Record browser evidence in reports or decision tables:

```text
Browser path: /route -> user action sequence
Auth method: real login | injected auth | mocked auth/backend
Browser RED: visible failing state before the fix, when part of a TDD bugfix
Browser GREEN: visible passing state after the fix, when part of a TDD bugfix
Evidence: visible state, selected value, disabled state, toast, route, etc.
Limitations: mocked backend, partial path, no real submit, etc.
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Judging UI behavior from source code only | Open the page and verify the user-visible boundary |
| Treating a component/unit RED as enough for a browser-visible bug | Add Browser RED before the fix and Browser GREEN after the fix |
| Treating a pending promise as a proven race | Hold it pending and check whether the user action is reachable |
| Skipping browser checks because login is inconvenient | Use test login, injected auth, or mocked fixtures |
| Using real sensitive accounts silently | Ask before sensitive browser actions or data transmission |
| Reporting "looks good" without evidence | Record path, auth method, evidence, and limitations |
