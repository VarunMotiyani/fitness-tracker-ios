# 09 — Tooling: Claude Code Skills & Plugins

_Date: 2026-08-27 · research pass_

What to use, what to install, what to build. Split by: **already available**
(this session / Superpowers), **worth installing** (Swift/iOS-specific, community),
and **build custom** (project skills).

> ⚠️ Community plugins/skills run instructions in your environment and vary in
> quality and maintenance. Vet before installing. Prefer Anthropic-official or
> well-known authors (e.g. twostraws). None of this is auto-installed — commands
> below are for you to run.

---

## A. Already available — use, don't install

### Process (Superpowers plugin)
| Skill | Used for |
|-------|----------|
| `superpowers:brainstorming` | Design phase — **done** |
| `superpowers:writing-plans` | **Next step** — Phase 1 implementation plan |
| `superpowers:executing-plans` / `superpowers:subagent-driven-development` | Running a plan with review checkpoints |
| `superpowers:test-driven-development` | Every feature — especially `RuleEngine` + `Validator` (safety-critical) |
| `superpowers:systematic-debugging` | Any bug / test failure |
| `superpowers:using-git-worktrees` | Isolated workspace per phase |
| `superpowers:requesting-code-review` / `receiving-code-review` | Before merging each phase |
| `superpowers:verification-before-completion` | Before claiming a phase done |
| `superpowers:finishing-a-development-branch` | Merging phase branches |
| `superpowers:writing-skills` | Building the custom skills in section C |

### Built-in slash skills
| Skill | Used for |
|-------|----------|
| `/code-review` | Diff / branch / PR review at chosen effort |
| `/security-review` | **Relevant** — app holds an API key in Keychain, later HealthKit data. Run before each merge. |
| `/simplify` | Quality/altitude cleanup passes |
| `claude-api` | **Relevant** — the `anthropic` adapter, plus structured-output / token-counting / caching / model-id reference for the whole AI layer. Read before building `AIClient`. |
| `/update-config` | Hooks & permissions (e.g. allow `xcodebuild`, `swift test`) |
| `/fewer-permission-prompts` | Auto-allowlist common `xcodebuild` / `swift` / `git` calls |
| `/init` | Generate `CLAUDE.md` once the repo has code |
| `/run` | Launch the app to confirm a change works |

### Not relevant to this project
`frontend-design` and all web-UI design skills (`dataviz`, `brandkit`, `design`,
`high-end-visual-design`, `artifact-*`, `make-interfaces-feel-better`, the
`*-taste-*` skills), `python-pytest-ops`, `keybindings-help`, `loop`, `schedule`.
- Marginal: `brandkit` could help with an app icon / name later;
  `dataviz` *principles* (palette, chart-type choice) could inform the InBody
  trend chart and cost sparkline even though they're built with SwiftUI Charts.

---

## B. Worth installing — Swift / iOS specific

### B1. XcodeBuildMCP  ★ highest value
MCP server: build, run on simulator, run tests, screenshot, UI-automation
(tap/swipe), LLDB debug — **without copy-pasting from Xcode**. ~80 tools.

```
claude mcp add xcodebuildmcp -- npx -y xcodebuildmcp@latest
# or: brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp
```

- **First check Xcode:** Xcode 26.3+ ships a **built-in MCP server** (project
  understanding, builds, tests). If the installed Xcode has it, that may be
  enough and XcodeBuildMCP becomes optional. Decide after checking the Xcode
  version.
- Without one of these, every build/test cycle is manual paste. With it, Claude
  closes the loop itself.

### B2. `build-ios-apps` marketplace plugin (anasdayeh, MIT)
Bundles commands + agents and wires up XcodeBuildMCP.
- Commands: `/build-ios-apps:doctor`, `run-simulator`, `performance-triage`,
  `swiftui-refactor`, `app-intents`
- Agents: `ios-workflow-orchestrator`, `swiftui-refactor-reviewer`,
  `ios-performance-triager`

```
/plugin marketplace add anasdayeh/build-ios-apps-marketplace
/plugin install build-ios-apps
```

Don't also keep a `~/.claude/skills/build-ios-apps` copy — one or the other.

### B3. One SwiftUI / Swift skill pack — pick one, not all
| Pack | Fit |
|------|-----|
| **`dpearson2699/swift-ios-skills`** | Explicitly **iOS 26+, Swift 6.3, SwiftUI, modern Apple frameworks** — matches our exact target. ~86 skills. **Recommended primary.** |
| `twostraws/SwiftUI-Agent-Skill` | Paul Hudson; focused SwiftUI API/design/perf/accessibility taste. Narrow, high quality. Good **secondary**. |
| `patrickserrano/skills` | `ios-debugger-agent`, `swift-concurrency-expert`, `swiftui-view-refactor`, `swiftui-performance-audit`, App Store release flows. |
| "Swift Development Assistant" (8 agents / 12 skills) | Broad; evaluate if the above don't cover concurrency + release. |

Recommendation: **`dpearson2699/swift-ios-skills`** primary, optionally
**`twostraws/SwiftUI-Agent-Skill`** for SwiftUI style.

### B4. Swift LSP plugin (optional)
SourceKit-LSP integration — real-time type-checking / completion / SwiftUI
preview signal outside Xcode. Useful for editing in VS Code; skippable if
building mostly in Xcode.

---

## C. Build custom — project skills (via `superpowers:writing-skills`)

Do these once patterns settle (after Phase 1), so future sessions follow our
decisions without re-reading every doc.

| Skill | Encodes |
|-------|---------|
| `fitness-core-conventions` | `FitnessCore` package boundaries; the `LLMProvider` adapter contract + `ProviderProfile` model; "AI output must validate against the catalog" rule; JSON-schema conventions; `AICallRecord` cost-ledger invariants; rule-engine-always-clamps-AI principle. Source: [03](03-technical-architecture.md), [06](06-decisions.md). |
| `catalog-curation` | Pull from `free-exercise-db`, remap to our `Exercise` schema, the ~100–150 selection criteria by movement pattern × equipment, license-file step. Source: [07](07-exercise-dataset-research.md). |
| `phase-workflow` | Branch per phase, TDD on `RuleEngine`/`Validator`, `/security-review` + `/code-review` gate, check the phase's "done when". Source: [04](04-roadmap-phases.md). |

---

## D. MCP servers beyond Xcode

Nothing else needed. No backend, no DB. GitHub is covered by the `gh` CLI
(already authed via the `github.com-personal` SSH path for pushes;
`gh` API for issues/PRs). A GitHub MCP is optional and not worth adding.

---

## Minimal recommended setup

1. Check Xcode version → built-in MCP, else install **XcodeBuildMCP** (B1).
2. Install **`build-ios-apps`** plugin (B2).
3. Install **`dpearson2699/swift-ios-skills`** (B3).
4. Use the Superpowers process skills already present (A).
5. After Phase 1, write the three custom skills (C).

Everything else (web-design skills, extra MCP servers) — not for this project.
