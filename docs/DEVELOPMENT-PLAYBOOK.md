# Development Playbook

How this project is designed, planned, built, reviewed, tested, and merged — end to end, in enough detail that a fresh agent (or a future skill / plugin) can follow it without prior context.

It has two layers:

1. **The Superpowers skill chain** — `brainstorming` → `writing-plans` → `subagent-driven-development` → `finishing-a-development-branch`. These are installed skills; this doc summarises how we actually run them and why.
2. **Project adaptations** — the concrete conventions this repo adds on top: the FitnessCore/app split, the exact test-gate commands, carry-forward docs, PR handling under an Enterprise-managed `gh` account, and the iOS Simulator acceptance-test tooling.

Everything marked **[project]** is our local convention, not part of the base skill.

---

## 0. TL;DR — the pipeline

```
idea
 └─ brainstorming ........... one question at a time → 2–3 approaches → sectioned design
      └─ SPEC  docs/specs/YYYY-MM-DD-<topic>-design.md   (committed)
           └─ writing-plans ... File Structure first → bite-sized tasks with REAL code
                └─ PLAN  docs/plans/YYYY-MM-DD-<feature>.md   (committed)
                     └─ subagent-driven-development
                          │  branch off main  +  ledger  +  pre-flight conflict scan
                          │
                          │  ┌─ per task ──────────────────────────────────────────┐
                          │  │ record BASE → task-brief → dispatch implementer      │
                          │  │   → implementer: TDD, commit, self-review, report    │
                          │  │ → review-package → dispatch task reviewer            │
                          │  │   → 2 verdicts: spec compliance + code quality       │
                          │  │ → fix loop (≤5 rounds): resume impl (1–3) /          │
                          │  │     fresh+stronger model (4–5) → scoped re-review    │
                          │  │ → ledger: "Task N: complete (commits a..b)"          │
                          │  └─────────────────────────────────────────────────────┘
                          │
                          │  after all tasks:
                          │   whole-branch final review (most capable model)
                          │    → ONE consolidated fix wave (F1, F2, …)
                          │    → ONE scoped re-review of the fix wave
                          │    → adjudicate residuals (park w/ ruling or rule + ledger)
                          │   collect every "Ruling:" line for the human
                          │   delete the SDD workspace
                          │
                          └─ finishing-a-development-branch
                               full test suite green → present 3 options → PR / merge
                                   └─ [project] Simulator acceptance testing
                                        └─ [project] carry-forwards doc → next phase
```

---

## 1. When to use this system

Use the full chain when the work is **architectural**: a new project, a new subsystem, or a change that restructures how components fit together or alters interfaces other code depends on.

Do **not** use it for:

- **Spikes** — feasibility questions ("can we…", "is X possible"). Output is an answer, not kept code. Say what you'll try in 2–3 sentences, get a nod, investigate as cheaply as correctness allows, report a recommendation.
- **Bounded changes** — a well-scoped change to code that already exists in the repo (a new flag, a one-file fix, a small endpoint). Ask the few clarifying questions that matter, present a short design *in chat*, get an explicit yes, then implement directly with TDD. No spec file, no plan document.

When in doubt between two paths, take the heavier one. The ratchet is one-way: hidden complexity discovered mid-task upgrades the path — stop, say so, step up. Nothing downgrades mid-task.

**The approval gate never scales away.** Every path ends with the human approving intent before implementation. A two-sentence design still gets an explicit "yes" before code.

---

## 2. Roles

| Role | Who | Context | Job |
|---|---|---|---|
| **Controller** | the main session | full — spec, plan, ledger, cross-task history | Decomposes, dispatches, reviews-by-proxy, rules on conflicts, keeps the ledger. Never writes task code itself. |
| **Implementer** | a fresh subagent, one per task | only what the dispatch hands it | Implements exactly one task, TDD, commits, self-reviews, writes a report file. Never dispatches anyone. |
| **Task reviewer** | a fresh subagent, one per task | brief + report + diff + constraints | Two verdicts: spec compliance, code quality. Read-only. Never dispatches anyone. |
| **Re-reviewer** | a fresh subagent, one per fix round | findings list + fix diff | Verdicts each finding ADDRESSED / NOT ADDRESSED; flags new breakage in the fix diff only. |
| **Final reviewer** | one subagent, most capable model | whole-branch diff + ledger's deferred/parked lines | One broad merge review. |
| **Human** | the repo owner | everything | Approves the spec, approves the design, picks the merge option, runs simulator acceptance, reads the rulings list. |

**Why subagents:** context isolation. The controller crafts exactly what each subagent needs so it stays focused and succeeds; the controller's own context stays clean for coordination. Fresh eyes per task catch what a long-running context normalises.

---

## 3. Phase decomposition & sub-plan splitting

Big features are split into **sequential sub-plans**, each of which:

- leaves the app **working and shippable** on its own,
- is **independently reviewable**,
- is split **by responsibility / subsystem**, never by technical layer.

**[project] worked example — Phase 2 "Run my session and remember it":**

- **2a** — `FitnessCore` foundation: pure `Metrics` + `CoachMemory` modules, progression rule promoted stub→real, `finalize` guardrail. No app changes. Exhaustive unit tests.
- **2b** — persistence + session runner: SwiftData `@Model`s, `@Observable SessionRunner`, Start/Focus/List/RestTimer/Summary screens. **Rule engine only, no AI** — the runner is fully exercised offline first.
- **2c** — the coach agents. *Split again* when it grew past ~10 tasks and covered two independent subsystems:
  - **2c-i** — AI session finalize behind the existing seam.
  - **2c-ii** — coach memory-keeper + progress analyst + recovery advisor + self-improvement loop.
- **2d** — history views + "what your coach knows" screen + pick-a-split.

**Split triggers:**

- the plan would exceed ~10 tasks, or
- it covers two subsystems that don't share a test surface, or
- one half could ship and be useful before the other is designed.

Each sub-plan gets its own spec section (or its own spec), its own plan file, its own SDD run, its own branch, its own PR.

---

## 4. Stage 1 — Brainstorming → Spec

Skill: `superpowers:brainstorming`. Announce it. **Do not write code, scaffold, or enter plan mode before the human approves the design.**

### 4.1 Process

1. **Explore context** — read files, docs, recent commits. Enough to frame good questions.
2. **Scope check** — if the request is really several independent subsystems, say so and decompose *before* spending questions on detail.
3. **Ask clarifying questions one at a time.** Prefer multiple-choice. One question per message. Focus on purpose, constraints, success criteria.
4. **Propose 2–3 approaches** with trade-offs; lead with your recommendation and why. YAGNI ruthlessly.
5. **Present the design in sections**, each scaled to its complexity (a few sentences up to ~300 words). Ask after each section whether it's right.
6. **Design for isolation:** every unit should answer "what does it do / how do you use it / what does it depend on" without reading its internals.

### 4.2 The spec document

Path: `docs/specs/YYYY-MM-DD-<topic>-design.md`. Commit it.

**[project] sections we use** (from the Phase 2 spec):

- Goal (one sentence) · Scope (in / out)
- Lifecycle / state machine
- The agent layer (which LLM call does what, when it fires)
- The `<core operation>` call — Input / Output schema / Guardrail / Fallback / Cost
- UI screens
- The data layer — typed core, extensible channel, derived rollups, query surface, scale
- Testing strategy
- **Resolved decisions** — numbered, each with rationale
- **Module / file impact**
- **Sub-plan breakdown** — the 2a/2b/2c/2d split, each a paragraph

### 4.3 Spec self-review (inline, no subagent)

- **Placeholder scan** — any "TBD", vague requirement? Fix.
- **Internal consistency** — sections contradict each other? Architecture matches the feature list?
- **Scope** — one implementation plan, or needs decomposition?
- **Ambiguity** — any requirement readable two ways? Pick one, make it explicit.

### 4.4 Human gate

> "Spec written and committed to `<path>`. Please review it and tell me if you want changes before we write the implementation plan."

Wait for an explicit yes. Changes → make them, re-run 4.3.

---

## 5. Stage 2 — Writing the Plan

Skill: `superpowers:writing-plans`. Announce it. Write for an engineer who is skilled but knows nothing about this codebase or domain and has questionable taste. Document everything.

### 5.1 Required header

```markdown
# [Feature] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> ... Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [one sentence]
**Architecture:** [2–3 sentences on approach]
**Tech Stack:** [key tech]
**Spec:** [path — the plan argues from the spec; executors read both]

## Global Constraints
[the spec's project-wide requirements, one line each, exact values verbatim]

---
```

### 5.2 File Structure section (before any task)

Map every file created or modified and its single responsibility. This locks the decomposition. Files that change together live together. Prefer small focused files.

### 5.3 Task right-sizing

A task is **the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate.** Fold setup/config/scaffolding/docs into the task whose deliverable needs them. Split only where a reviewer could reject one task while approving its neighbour. Each task ends with an independently testable deliverable.

### 5.4 Task structure

````markdown
### Task N: [Component]

**Files:**
- Create: `exact/path.swift`
- Modify: `exact/path.swift:120-145`
- Test: `exact/tests/path.swift`

**Interfaces:**
- Consumes: [what earlier tasks produce that this uses — exact signatures]
- Produces: [what later tasks rely on — exact names, param/return types]

- [ ] **Step 1: Write the failing test**  ```<real test code>```
- [ ] **Step 2: Run it, watch it fail**   Run: `<command>`  Expected: FAIL "<reason>"
- [ ] **Step 3: Minimal implementation**  ```<real impl code>```
- [ ] **Step 4: Run it, watch it pass**   Run: `<command>`  Expected: PASS
- [ ] **Step 5: Commit**                  ```git add … && git commit -m "…"```
````

**The `Interfaces` block is how a subagent that only sees its own task learns the names and types its neighbours use.** Keep them consistent across tasks — `clearLayers()` in Task 3 and `clearFullLayers()` in Task 7 is a bug.

### 5.5 No placeholders — these are plan failures

- "TBD", "implement later", "add error handling", "handle edge cases"
- "Write tests for the above" without the test code
- "Similar to Task N" — repeat the code; tasks are read out of order
- Steps describing *what* without *how* (code steps need code blocks)
- References to types/functions defined in no task

### 5.6 Plan self-review (inline)

1. **Spec coverage** — point to a task for every spec requirement. List gaps, add tasks.
2. **Placeholder scan** — kill every pattern in 5.5.
3. **Type consistency** — signatures/names in later tasks match earlier definitions.

### 5.7 Execution handoff

Offer the two execution modes and let the human pick:

1. **Subagent-Driven** (this project's default) — fresh subagent per task, review between tasks, fast iteration.
2. **Inline** — `superpowers:executing-plans`, batch execution with checkpoints.

---

## 6. Stage 3 — SDD setup

Skill: `superpowers:subagent-driven-development`. Announce it.

### 6.1 Workspace

- **Branch** off `main` (or a worktree). Never start on `main` without consent. **[project]** branch name = the plan basename without the date, e.g. `phase-2c-i-ai-session-finalize`.
- **Ledger** at `<repo>/.superpowers/sdd/<plan-basename>/progress.md`. This directory is **gitignored scratch** — it holds the ledger, task briefs, task reports, review packages, the final-review report, the fix-wave brief/report. Resolve it with the skill's `scripts/sdd-workspace PLAN_FILE`.
- **Never** read or write another plan's workspace directory.
- Conversation memory does not survive compaction. **The ledger + `git log` are the recovery map** — trust them over recollection. Controllers that lost their place have re-dispatched entire completed task sequences; the ledger prevents that.

### 6.2 Ledger identity & resume

First line: `# SDD ledger — plan: <plan file path>`.

On skill start, if a ledger already exists and its first line names *this* plan: tasks with a `Task N: complete` line are **done — do not re-dispatch**. Resume at the first task without one. A task whose last line is a fix round is mid-loop — resume the loop at the next round.

### 6.3 Pre-flight conflict scan

Before dispatching Task 1, scan the plan once and **write a table to the ledger** — not a verdict, a table:

- one row per **pair of tasks that share a file or interface**: what one produces vs what the other consumes, and what you found;
- one row per **task's internal consistency**: do its own tests match its own code, do the files it creates match the files it later touches.

"The scan is clean" without those rows is not a scan. Rule on every conflict the scan surfaces — spec is the binding authority — record each ruling beside its row, then dispatch Task 1.

**[project] example (Phase 2c-i ledger):**

```
## Pre-flight conflict scan
| Rows checked | Finding |
|---|---|
| T1 (drop MetricsRepository: Sendable) vs "FitnessCore in scope" constraint | consistent — plan re-opens FitnessCore for T1/T2 only |
| T3 renames SessionFinalizer→RuleEngineFinalizer; T5/T6 consume that name | consistent — names fixed in T3 Interfaces block |
| T4 reuses CallOutcome from PlanCoordinator.swift (not redefined) | consistent |
| ... | ... |
Scan clean. No rulings needed pre-execution.
```

---

## 7. Stage 4 — the per-task loop

### 7.1 Dispatch the implementer

1. **Record BASE:** `git rev-parse HEAD` — the review package and every fix-round diff need it. **Never `HEAD~1`** (silently drops all but the last commit of a multi-commit task).
2. **Task brief:** `scripts/task-brief PLAN_FILE N` → writes `task-N-brief.md`, prints the path. This file is the single source of requirements.
3. **Compose the dispatch** (use `implementer-prompt.md`). It contains exactly:
   1. one line on where this task fits in the project;
   2. the brief path — "read this first; it is your requirements, with the exact values to use verbatim";
   3. interfaces and decisions from earlier tasks that the brief can't know;
   4. your resolution of any ambiguity you noticed in the brief;
   5. the report-file path (`task-N-report.md`) and the report contract.
   - Exact values (numbers, magic strings, signatures, test cases) live **only in the brief**. Never make a subagent read the whole plan.
   - **Never paste session history or "state after Tasks 1–3" into a dispatch.** A real session's dispatch once hit 42k chars, 99% pasted history. A fresh subagent needs its task, its interfaces, the global constraints. Nothing else.
   - Hand artifacts as **files**, never pasted into the prompt — everything pasted stays resident in the controller's context for the rest of the session.
4. **Record the implementer's agent id** from the dispatch result — fix rounds 1–3 resume it.
5. **Never run two implementers in parallel** (merge conflicts).

### 7.2 Model selection — always specify explicitly

An omitted model silently inherits the session's most expensive one.

| Task shape | Model |
|---|---|
| Plan text contains the complete code to write → transcription + testing | cheapest tier (e.g. Haiku) |
| Single-file mechanical fix | cheapest tier |
| 1–2 files, complete spec, mechanical | cheap/fast |
| Multi-file, integration concerns, from prose | standard (mid-tier is the floor for prose work) |
| Architecture / design judgment / broad codebase understanding | most capable |
| **Final whole-branch review** | most capable, explicitly — not the session default |
| Reviewers | scaled to diff size/risk; small mechanical diff → cheap-to-mid; subtle concurrency → most capable |
| **Fix-loop rounds 4–5** | at least one tier above the implementer that got stuck |

**Turn count beats token price.** The cheapest models take 2–3× the turns on multi-step work and cost more overall. Wall-clock and context cost scale with turns.

**[project]** Task 1 (mechanical, complete code) ran on Sonnet only because it's toolchain-heavy (xcodebuild iteration); pure-transcription tasks drop to Haiku.

### 7.3 Batch small same-shape work

Several tasks that are each the same one-line edit across files → **one dispatch** listing every file and its change, reviewed as one diff. Reserve one-dispatch-per-task for work that needs its own judgment, tests, or review surface.

### 7.4 Handle the implementer's report — four statuses

- **DONE** → generate the review package, dispatch the task reviewer.
- **DONE_WITH_CONCERNS** → read the concerns first. Correctness/scope concern → address before review. Observation ("this file is getting large") → note and proceed.
- **NEEDS_CONTEXT** → provide what's missing, re-dispatch.
- **BLOCKED** → assess: context problem → more context, same model; needs more reasoning → stronger model; too large → split; plan is wrong → rule on the fix, ledger it, re-dispatch with the ruling. **Never** ignore an escalation or force the same model to retry unchanged.

If the implementer asks questions before or mid-task, answer completely; don't rush it into implementation.

### 7.5 The task review

`scripts/review-package PLAN_FILE BASE HEAD` → one file with commit list + `git diff --stat` + `git diff -U10`. The package never enters the controller's context.

Dispatch `task-reviewer-prompt.md` with **four inputs**: brief file, report file, review package path, and the **Global Constraints copied verbatim from the plan/spec** — exact values, formats, stated relationships between components ("same layout as X"). That constraints block is the reviewer's attention lens; the template already carries the process rules (YAGNI, test hygiene, review method).

**Reviewer returns two verdicts, both required:**

- **Part 1 Spec Compliance** — ✅ / ❌ (Missing / Extra / Misunderstood, with file:line) / ⚠️ "cannot verify from diff".
- **Part 2 Code Quality** — separation of concerns, error handling, DRY-without-premature-abstraction, edge cases, tests verify real behaviour, file responsibility/size (only what *this* change contributed).

Never accept a report missing either verdict. Implementer self-review never replaces the task review.

**Controller hygiene when writing the reviewer prompt:**

- No open-ended directives ("check all uses", "run race tests if useful") without a concrete task-specific reason.
- Don't ask the reviewer to re-run tests the implementer already ran on the same code.
- **Never pre-judge:** no "do not flag X", "at most Minor", "the plan chose this". If your prompt contains any of those, stop — you're sparing yourself a review loop. Let the reviewer raise it; adjudicate in the loop.

**⚠️ items** don't block the rest of the review, but the controller must resolve each one before marking the task complete (you hold the cross-task context the reviewer lacks). A confirmed gap becomes a failed spec review and enters the fix loop.

### 7.6 The fix loop — ≤ 5 rounds per task

Triggers on: spec ❌, any Critical or Important finding, or a ⚠️ you confirmed.

Two immediate exits *before* the loop:

- **Minor findings** never enter the loop. Ledger each: `Task N: minor (deferred): <one-liner>`. Point the final review at that list.
- A **plan-mandated** finding, or any finding that conflicts with the plan text, is the controller's to **rule on** (spec is binding) and **ledger before acting**. Don't dismiss it because the plan mandates it; don't dispatch a fix that contradicts the plan without a recorded ruling.

A round = one fix dispatch + one scoped re-review.

- **Rounds 1–3** — resume the original implementer (its context is intact). Send the open findings verbatim. If the harness can't message a live subagent, dispatch fresh with the brief path + report-file path + findings (the report file is the persistent memory).
- **Rounds 4–5** — fresh implementer, **model one tier up**, framed: "A prior implementer attempted this [N] times; you own it now. Read the report file for what was tried." Three survived resumes usually means the implementer can't see its own problem.
- **Every round:** implementer fixes → re-runs the tests covering the amended code → appends a fix report to the same report file → returns the short contract. Confirm the fix report has covering tests + command + output *before* dispatching the re-review. Name the covering test files in the fix message — a one-line fix doesn't need the whole suite.
- **Scoped re-review:** `scripts/review-package PLAN_FILE FIX_BASE HEAD` (FIX_BASE = the head the previous review saw). Dispatch `re-review-prompt.md` with the findings list + brief + report + diff path. Re-reviewer verdicts each finding **ADDRESSED / NOT ADDRESSED** and flags new breakage **in the fix diff only**. New Critical/Important breakage in the fix diff joins the open findings. Out-of-scope observations → ledger as deferred minors, never extend the loop.
- **Ledger each round:** `Task N: fix round R/5 (X addressed, Y open — <one-liners>; commits a7..b7)`.
- **Never fix findings yourself in the controller session** — it pollutes your context and skips review.

**The breaker (round 5 still open):** stop dispatching. Adjudicate each open finding — you hold the plan and cross-task context:

- reviewer wrong / contestable → park: `Task N: parked — <finding> — Ruling: <why the code stands>`.
- real but nothing builds on it → park with a ruling saying it's real and deferred.
- **real and load-bearing** (a later task builds on it, or it's a plan defect) → rule on the smallest change that unblocks the dependent work, ledger `Task N: Ruling: <finding> — <decision and why>`, carry it into the next task's dispatch. Stop entirely only when every path forward is a guess.

Adjudicate **only at the cap** — adjudicating early to end a loop is pre-judging with another name.

### 7.7 Complete the task

Review clean, or every open finding parked-with-ruling at the cap:

- `Task N: complete (commits <base7>..<head7>, review clean)`
- `Task N: complete (commits <base7>..<head7>, K parked)` after a tripped breaker

Mark the todo done. **Never** move to the next task with unresolved Critical/Important findings that are neither fixed nor parked-with-ruling at the cap.

### 7.8 Continuous execution

Do **not** check in with the human between tasks. Execute all tasks. "Should I continue?" and progress summaries waste their time. Between tool calls, narrate at most one short line — the ledger and tool results carry the record.

The **only** four things that stop you:

1. an irreversible or destructive operation,
2. a security-sensitive action,
3. a side effect outside this worktree that norms say you ask about first (a merge, a push to a shared branch, a publish),
4. a plan so broken every path forward is a guess.

Everything else: decide, ledger the ruling, keep going.

---

## 8. Stage 5 — the whole-branch final review

After the last task:

1. `scripts/review-package PLAN_FILE MERGE_BASE HEAD` where `MERGE_BASE = git merge-base main HEAD`.
2. Dispatch **one** reviewer, **most capable model**, using `superpowers:requesting-code-review`'s `code-reviewer.md`. Point it at the ledger's deferred-minor and parked lines so it can triage what must be fixed before merge.
3. It classifies findings **Critical / Important / Minor** and returns a verdict ("merge" / "merge WITH FIXES" / "do not merge").
4. **One consolidated fix dispatch** — not one fixer per finding. Per-finding fixers each rebuild context and re-run suites; a real session's final-review fix wave cost more than all its tasks combined.
5. **One** scoped re-review of the fix-wave diff (`review-package PLAN_FILE FIX_BASE HEAD`, `re-review-prompt.md`).
6. Adjudicate residuals as in the breaker: park with rulings, or rule on the load-bearing ones and ledger. **There is no second fix wave** — residual load-bearing findings surface to the human at finish time.

### 8.1 [project] The fix-wave brief structure

The brief we hand the fix-wave implementer (from the Phase 2b run):

```
# Phase <X> — final fix wave

The whole-branch review (final-review.md, same dir — READ IT for exact file:line
+ fix recipes) returned "merge WITH FIXES". This is the single consolidated
fix dispatch. Branch <branch>, HEAD <sha>. <scope: app target only / etc>.

Global constraints still bind: <restated verbatim>. Small commits (per F-item
or tight cluster). At the end: <the exact test-gate commands>.

---
## REQUIRED — Critical
### F1 — C1: <title>
<file:path — function>. <what's wrong, with the failure scenario>.
**Fix:** <recipe, numbered steps, real code>.
Test: <what to assert>.

### F2 — C2: <...>

## REQUIRED — Important
### F3 — I1: <...>
...

## REQUIRED — cheap Minors (you're in these files anyway)
- <one-liners>

## CARRY FORWARD to the Phase <X+1> plan (do NOT do now — record only):
- <item> — <why> — <where it bites>

---
## Report
Full report → <dir>/fix-wave-report.md (files touched; per F-item + each
cheap-Minor FIXED / PARTIAL / SKIPPED + one line; commit list; final test
counts; anything incomplete).
Return to the controller ONLY: status, commit range first..last, the suite
pass-counts on one line, any item not completed.
```

### 8.2 Finish

- Collect **every ledger line containing `Ruling:`** — pre-flight rulings, parked findings, breaker adjudications — into the final message under **"Rulings I made"**, in order, each with what it costs if wrong. This is the only place decisions taken on the human's behalf reach them. A ruling that dies with the workspace was a secret decision.
- When the final review is clean and merged: `rm -rf <this plan's workspace>`. Git history is the record now. Leave sibling directories alone.
- Then: `superpowers:finishing-a-development-branch`.

---

## 9. Stage 6 — finishing a development branch

Skill: `superpowers:finishing-a-development-branch`. Announce it.

1. **Verify tests.** Run the full suite on the tree you're about to integrate. **[project]** both:
   ```
   cd FitnessCore && swift test 2>&1 | tail -6
   xcodebuild test -scheme FitnessTracker \
     -destination 'platform=iOS Simulator,id=B29C47DD-D3FE-490C-9A84-3D9A32AFE68A' \
     -project FitnessTracker/FitnessTracker.xcodeproj 2>&1 | tail -20
   ```
   Failing → report failures and stop. The menu comes after a green suite.
2. **Detect environment** (normal repo vs worktree vs detached HEAD) — decides the menu and cleanup.
3. **Confirm the base branch** ("this split from `main` — correct?"). Merging into the wrong base is expensive to undo.
4. **Present exactly these 3 options** (normal repo / named-branch worktree):
   ```
   1. Merge back to <base> locally
   2. Push and create a Pull Request
   3. Keep the branch as-is
   ```
   Present as written. Wait for the answer. Discarding work happens **only** when the human types the word `discard`.
5. **Execute:**
   - *Merge locally* — checkout base, pull, merge, re-run the suite on the merged result, then delete the branch + clean the worktree.
   - *PR* — `git push -u origin <branch>`, open the PR against base with the forge tooling, report the URL. Keep the worktree for PR feedback.
6. **Cleanup** (Option 1 / confirmed discard only): remove a superpowers-created worktree (`.worktrees/…`), `git worktree prune`. Removal refused for uncommitted files → show the human, ask, never `--force` on your own.

### 9.1 [project] PR content convention

`gh` on this machine is signed in as an **Enterprise-managed account that cannot open PRs on the personal repo**. So: push, then give the human the compare URL plus a paste-ready title and body.

**Body shape:**

- **Why** — root cause or motivation, with **evidence** (the `sample` stack, the failing assertion, the spec section).
- **What changed** — a per-commit narrative, **including wrong turns** ("`b618e5c` — an earlier attempt; `885ae8a` supersedes it").
- **Testing** — a table: scenario/screen × before/after.
- **Out of scope** — what this deliberately doesn't touch.

Commit messages: imperative, plain, **no `Co-Authored-By` trailer**, **no push without the human asking**.

---

## 10. Stage 7 — [project] iOS Simulator acceptance testing

After merge, the human runs an acceptance checklist (groups A/B/C in the last task's report). The agent can drive the Simulator itself — no `idb` on this machine:

| Need | Tool |
|---|---|
| See the screen | `xcrun simctl io <UDID> screenshot out.png` then Read the PNG |
| Tap | `osascript -e 'tell application "System Events" to click at {x, y}'` — map screenshot px → screen coords via the Simulator window's `position`/`size` (`osascript … get {position, size} of window 1`) |
| Type | `xcrun simctl io` has no text input; use System Events `keystroke` while the sim is frontmost |
| Detect a hang | `sample <pid> 3 -mayDie` |
| Install / launch / kill | `xcrun simctl install|launch|terminate <UDID> com.varunmotiyani.FitnessTracker` |

**Reading a `sample`:**

- Main thread in `__CFRunLoopRun` → `mach_msg2_trap` = **healthy idle**, waiting for events.
- A deep **non-repeating** call tree ending in a single sync barrier (`_dispatch_lane_barrier_sync_invoke_and_complete`) that never returns across successive samples = **deadlock**.
- The **entire** sample pinned in one call subtree = either one pathological call (e.g. `NSSQLGenerator` thrash) or a synchronous re-render loop. Decreasing sample counts down one stack = going deeper into one call; equal counts at each level of a shallow loop = looping.

**Limitation:** synthetic `click at` does not reliably activate SwiftUI `List`-row `NavigationLink`s — the human confirms those by hand.

**Worked example — the `#Predicate` hang:** two fixes were wrong (toolbar `NavigationLink`; `$0.isActive == true`). The `sample` showing the main thread pinned in `NSSQLGenerator` / `_generateSQLForKeyPathExpression` lowering the predicate pinpointed the predicate itself. Fix: drop the `#Predicate` from `@Query`, filter `.isActive` in Swift. **Don't ship a guess — sample, read the stack, form a hypothesis, test it.**

---

## 11. Cross-cutting: Rulings

A running plan does not wait on a human. Conflicts, ambiguities, plan defects, a cap you'd have asked to exceed — decide them.

**Format** (every ruling, everywhere — pre-flight, fix loop, breaker):

```
Ruling: <what you decided> — <why> — <what it costs if wrong>
```

A wrong ruling costs rework the human can see and undo. A session parked on a question costs their whole day and buys nothing.

**[project] examples from Phase 2b:**

- `Ruling 2: SwiftDataMetricsRepository is a @MainActor struct with nonisolated func + MainActor.assumeIsolated bodies — because MetricsRepository: Sendable forbids main-actor isolation on the conformance — cost if wrong: an off-main call compiles and traps at runtime` *(later discharged by Phase 2c-i Task 1)*
- `Ruling 4: added Metrics + CoachMemory as explicit XCSwiftPackageProductDependency in project.pbxproj mirroring RuleEngine — because import CoachMemory fails without the app target linking them — cost if wrong: build break, easily reverted`
- `Ruling 8: finish() runs exactly once, from SessionSummaryView stage-1 Save; the list's Finish calls requestSummary() — cost if wrong: double PR detection / clobbered partial reason`

Every ruling is a ledger line. A silent discard is forbidden.

---

## 12. Cross-cutting: the Ledger format

```
# SDD ledger — plan: docs/plans/2026-08-30-phase-2c-i-ai-session-finalize.md

Branch: phase-2c-i-ai-session-finalize
BASE (plan commit): 0a27669…

## Pre-flight conflict scan
| Rows checked | Finding |
| … | … |
Scan clean. / Ruling: …

## Tasks

### Task 1: <name>
- Dispatched: implementer <agent-type> / <model>, id <agentId>, BASE <sha>
- Implementer DONE: commit <sha>. <one-line test result>.
- Task review dispatched: <agent-type> / <model>, package <file>
- Task 1: fix round 1/5 (2 addressed, 0 open — <one-liners>; commits <a>..<b>)
- Task 1: complete (commits <base7>..<head7>, review clean)

### Task 2: …
```

- First line = identity. After compaction, the controller trusts this file + `git log` over its own memory.
- `.superpowers/` is gitignored → **the ledger does not travel between machines.** Anything that must survive the branch goes in a committed doc (§13).

---

## 13. Cross-cutting: Carry-forwards

Deferred/parked items that must outlive the SDD run get a **committed** doc:

`docs/plans/YYYY-MM-DD-phase-<X>-followups.md`

**[project] contents** (from `2026-08-29-phase-2a-followups.md`):

- a header noting the branch + HEAD + test counts at hand-off,
- items grouped **by the future phase that picks them up** (`### For Phase 2b`, `### For Phase 2c`, `### For Phase 2d`),
- each item: an `R<n>` / `T<n>` tag, the precise defect, the narrow conditions it bites under, the fix recipe, and whether it's blocking or cosmetic,
- a `## Cosmetic / non-blocking (do when touching the file)` section.

The next phase's plan **reads this doc** (named in its `Spec:` line or Global Constraints), folds the relevant items into its own tasks, and ticks them off in a `## Discharged in Phase <Y>` section with the commit subjects.

The whole-branch fix-wave brief also carries a `## CARRY FORWARD` section (§8.1) that feeds this doc.

---

## 14. Cross-cutting: model & rate-limit operations

- **Opus subagents hit the account session rate limit (HTTP 429)** during long fix waves. Adopted: run **final reviews on the most capable model**, fall back to **Sonnet for fix implementers**; keep stall-watchers armed.
- **A reviewer died silently after ~5 hours with no completion notification** and the controller loop stalled waiting. Adopted: **active bounded check-back watchers** — a `run_in_background` bash loop watching the subagent transcript's mtime — instead of notification-only waits. If a child goes quiet past a threshold, re-dispatch a fresh one.
- **Never** poll a wait interface with short timeouts. When genuinely idle, wait in **5–10 minute bounded stretches**; between them post one status line and reconcile live children (list them, chase any that finished without reporting). A bounded stretch keeps ~all of a long wait's efficiency while guaranteeing a stuck child is noticed in minutes.
- While waiting, do local work — ledger updates, packaging the next review, reading reports. Child results arrive on their own.

---

## 15. Cross-cutting: testing philosophy [project]

- **New logic:** Swift Testing — `import Testing`, `@Test`, `@Suite`, `#expect`. `@MainActor` on test structs that touch SwiftData.
- **UI / launch:** XCTest.
- **SwiftData:** in-memory `ModelContainer(for: …, configurations: ModelConfiguration(isStoredInMemoryOnly: true))` for round-trip tests.
- **AI paths:** `StubLLMProvider` — exercise generate → validate → retry → fallback with no network. Cases per coordinator: clean first call, retry-then-succeed, retry-then-fallback, throw-then-fallback, no-provider.
- **Pure `FitnessCore` modules:** exhaustive unit tests — this is the safety-critical layer.
- **No real network anywhere.**
- **Test-count gates** in every task's final step and at phase end. A dropped count is a regression to explain, not wave through. Test output must be **pristine** — warnings are findings.
- **TDD** where the plan says so: write the failing test, run it, watch it fail *for the stated reason*, minimal impl, run it pass, commit. The implementer's report carries the RED and GREEN evidence — reviewers do not re-run.

---

## 16. File & naming conventions [project]

| Path | What |
|---|---|
| `docs/specs/YYYY-MM-DD-<topic>-design.md` | spec (committed) |
| `docs/plans/YYYY-MM-DD-<feature>.md` | implementation plan (committed) |
| `docs/plans/YYYY-MM-DD-phase-<X>-followups.md` | carry-forwards (committed) |
| `docs/HANDOFF.md` | living status — **read first**, updated every phase |
| `docs/04-roadmap-phases.md` | phase roadmap |
| `.superpowers/sdd/<plan-basename>/progress.md` | the ledger (gitignored) |
| `.superpowers/sdd/<plan-basename>/task-N-brief.md` | task requirements, from `scripts/task-brief` |
| `.superpowers/sdd/<plan-basename>/task-N-report.md` | implementer report + appended fix reports |
| `.superpowers/sdd/<plan-basename>/review-<base>..<head>.diff` | review package, from `scripts/review-package` |
| `.superpowers/sdd/<plan-basename>/final-review.md` | whole-branch review report |
| `.superpowers/sdd/<plan-basename>/fix-wave-brief.md` / `fix-wave-report.md` | the consolidated final fix wave |
| branch name | plan basename minus date, e.g. `phase-2c-i-ai-session-finalize` |
| commit messages | imperative, plain, **no `Co-Authored-By`**, no push without asking |
| Xcode scheme | `FitnessTracker` (shared scheme + `FitnessTracker.xctestplan` committed) |
| Simulator | iPhone 17 Pro, iOS 26.5, UDID `B29C47DD-D3FE-490C-9A84-3D9A32AFE68A` |
| bundle id | `com.varunmotiyani.FitnessTracker` |

---

## 17. Templates appendix

### 17.1 Implementer dispatch (skeleton)

```
Subagent (general-purpose):
  model: <cheap|standard|capable — explicit>
  prompt: |
    You are implementing Task N: <name>, for the "<plan title>" plan.

    ## Task Description
    Read your task brief first — it is your requirements, with the exact code
    to use verbatim: <abs path to task-N-brief.md>

    Work from: <repo root>.  Branch (checked out): <branch>.

    ## Context
    <1–3 sentences: where this fits, what earlier tasks produced that this consumes>

    ## Before You Begin
    If anything in the brief is unclear or you hit an unexpected error you
    can't resolve from the brief, ask before guessing.

    ## Your Job
    1. Follow the brief's steps exactly (TDD where it says to).
    2. Gates: <the exact test commands + expected counts>.
    3. Commit with the exact message in the brief's final Step.
    4. Self-review your diff (completeness / quality / discipline / testing).
    5. Write your full report to: <abs path to task-N-report.md>

    Constraints: plain commit message, NO Co-Authored-By. Do NOT git push.
    Do NOT dispatch subagents. Do NOT commit anything under .superpowers/.

    ## Report Format
    Full report to the file above. Then reply with ONLY (<15 lines):
    - Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - Commit(s): short SHA + subject
    - One-line test summary
    - Concerns, if any
    - The report file path
```

### 17.2 Task-reviewer dispatch — see `task-reviewer-prompt.md`; supply BRIEF_FILE, GLOBAL_CONSTRAINTS (verbatim), REPORT_FILE, BASE_SHA, HEAD_SHA, DIFF_FILE, MODEL.

### 17.3 Scoped re-review dispatch — see `re-review-prompt.md`; supply BRIEF_FILE, FINDINGS (verbatim, one per bullet), REPORT_FILE, FIX_BASE_SHA, HEAD_SHA, DIFF_FILE, MODEL.

### 17.4 PR body (skeleton)

```
## Why
<root cause / motivation, with evidence — sample stack, failing assertion, spec §>

## What changed
- `<sha>` <subject> — <one line, including if it's a superseded wrong turn>

## Testing
| Scenario | Before | After |
|---|---|---|
| … | … | … |

<what's out of scope>
```

---

## 18. Worked example — Phase 2b, end to end

1. **Spec** — `docs/specs/2026-08-29-phase-2-session-runner-design.md` §3 (lifecycle), §5.4 (rule-engine finalisation), §6 (runner UI), §8.1 (typed core), §14 (2b bullet). Committed.
2. **Plan** — `docs/plans/2026-08-29-phase-2b-persistence-session-runner.md`, 12 tasks. Global Constraints: **app target only, FitnessCore frozen**; Xcode 26 `@MainActor` default; no AI/network; API keys untouched; plain commits; test gate = `xcodebuild test … -id=B29C47DD…` + `cd FitnessCore && swift test`.
3. **SDD** — branch `phase-2b-persistence-session-runner`, ledger created, pre-flight scan table written (clean).
4. **Task loop** — 12 tasks, fresh implementer each (Sonnet for integration, Haiku for transcription), task review each. Rulings recorded inline (e.g. Ruling 2, 4, 8 above). Notable task-review catch: T6 `logSet` read the finalized item **positionally**, so targets were wrong after `reorder` → fixed to match by `exerciseID` (`fcd3f15`).
5. **Whole-branch review** — dispatched on the most capable model. Verdict "merge WITH FIXES": **2 Critical + 6 Important**.
   - C1: logged sets on entries never ticked "Done" contributed **zero** to metrics/PRs/volume (`countsTowardMetrics` needs `state == .done`; `logSet` only set `.inProgress`).
   - C2: per-exercise summary notes lost unless the user pressed Return.
6. **Fix wave** — one consolidated brief (`fix-wave-brief.md`), F1–F7 + cheap Minors + a CARRY FORWARD section. 5 commits. F1: `promoteWorkedEntries` promotes worked-but-unticked entries to `.done` in `finish()` and `resolveAbandoned` *after* computing the outcome.
7. **Scoped re-review** of the fix-wave diff — clean.
8. **Finish** — full suite green (96 + new, 126 FitnessCore) → Option 2 (PR). `gh` blocked (EMU) → compare URL + paste-ready body → human merged as **PR #5**.
9. **Simulator acceptance** — human hit the `#Predicate` hang (§10 worked example); fixed on a follow-up branch, merged as **PR #7**.
10. **Carry-forwards** — `2026-08-29-phase-2a-followups.md` items R1/R5 + three new ones (fix `MetricsRepository: Sendable`; extract async `SessionFinalizing`; `@Attribute(.unique)` on `CoachMemoryModel.id`) → folded into the **Phase 2c-i plan** (Tasks 1–3 + a 2c-ii carry-forward list).

---

## 19. Glossary

| Term | Meaning |
|---|---|
| **Controller** | the coordinating session; owns the plan, ledger, dispatch, rulings |
| **Implementer** | one-task subagent; TDD, commit, report; never dispatches anyone |
| **Task review** | per-task gate: spec-compliance verdict + code-quality verdict |
| **Fix loop** | ≤5 rounds of fix-dispatch + scoped re-review for a task's findings |
| **Scoped re-review** | verifies each finding ADDRESSED/NOT ADDRESSED + new breakage in the fix diff only |
| **Breaker** | round-5 cap; controller adjudicates each open finding (park w/ ruling, or rule + carry forward) |
| **Whole-branch / final review** | one broad merge review on the most capable model after all tasks |
| **Fix wave** | the single consolidated fix dispatch answering the final review (F1, F2, …) |
| **Ruling** | `Ruling: <decision> — <why> — <cost if wrong>`; every one is a ledger line, all surfaced to the human at finish |
| **Ledger** | `.superpowers/sdd/<plan>/progress.md`; the compaction-proof recovery map |
| **Carry-forward** | a deferred item recorded in a committed `phase-<X>-followups.md` for a later phase |
| **Review package** | `scripts/review-package` output: commit list + stat + `git diff -U10`, as one file |
| **BASE** | `git rev-parse HEAD` recorded *before* a task's dispatch; never `HEAD~1` |
| **Global Constraints** | the plan section copied verbatim into every reviewer prompt as its attention lens |
