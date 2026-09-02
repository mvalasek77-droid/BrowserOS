# Cinema Composer Pro

**The conductor for an orchestra of AI tools that make feature films.**

A native iOS/iPadOS app (SwiftUI, iOS 17+) that does the jobs the current crop of AI video tools leaves to a spreadsheet:

| | |
|---|---|
| **Producer** | Breaks a runtime down into scenes, shots, dialogue minutes and foley events, then prices all of it — including storage, egress, failed generations you still get billed for, human review hours and contingency. |
| **Advisor** | Ranked, *measured* ways to spend less. Every suggestion is the whole picture re-planned with that change applied, with the tradeoff stated and a button that makes it. |
| **Conductor** | Assigns a tool to every job, schedules the task graph under per-vendor concurrency limits, retries what is retryable, and halts the moment spend would pass a hard cap. |
| **Optimizer** | Six efficiency passes, each priced by replanning without it, against a "pick the best model and press go" baseline. |
| **Cutting room** | A real NLE — blade, ripple, trim, slip, overwrite, takes — where every clip also knows which tool generated it, from which prompt, for how much. |

Dry runs cost nothing and need no API keys. Live runs need keys, and say so before they spend a cent.

---

## Where things live

```
CinemaComposerPro/
  Models/      FilmSpec, tiers, genres, strategies · AITool, pricing, semver · Scenario, templates
  Engine/      ToolCatalog · ToolRegistry · BreakdownEngine · Planner · BudgetEngine
               Advisor · ShotEconomics · Conductor · ToolAdapter · Timeline · Exporters
  Extensions/  BudgetModule protocol + Festival delivery, Marketing package
  Services/    KeychainStore · ProjectStore · Formatters
  ViewModels/  ProductionViewModel — the single source of truth
  Views/       Producer · Advisor · Efficiency · Conductor · Cutting room · Shot economics
               Scenarios · Tool rack · Keys · Setup · Charts
  Packs/       example-vendor-pack.json — the template for wiring a real vendor
CinemaComposerProTests/   engine invariants: breakdown, planner, budget, advisor, shot
                          economics, rack, timeline, conductor, exports
```

Build with XcodeGen like the rest of the repo:

```sh
xcodegen generate
open SteroidOS.xcodeproj      # scheme: CinemaComposerPro
```

---

## The producer

`Breakdown.make(from:)` turns *"96-minute sci-fi thriller, theatrical tier"* into a deterministic shot list — seeded, so the same spec always yields the same budget — and a workload in the units vendors actually bill in. `BudgetEngine` prices it and reports what a financier asks for:

- line items by department, with tool, units, rate and subtotal
- **unit economics**: per runtime minute, per finished second, per shot, per scene
- AI share vs human share — on a real feature, supervision is usually the biggest single line, and the app says so instead of hiding it
- the runtime cost curve and a tier × strategy heat grid
- **shot economics**: photography spend attributed back to individual shots, so you can see which forty seconds of film are eating the budget — and swipe to route one to a cheaper generator
- exports: a producer's **top sheet** (Markdown), the full budget (CSV)

If some department cannot be staffed — no tool on the rack, or no key for the only tool that can do it — the app reports a **gap** and marks the budget incomplete. A budget that silently omits Photography is worse than no budget.

## The advisor

Not a tips list: a re-planner. For each candidate change — a different strategy, a tier down, six minutes out of the script, fewer takes per keeper, fewer shots on the hero model, a pass you left off, a supervision rate you never chose — it re-plans the entire picture and reports the true delta, then states what taking it costs you. One tap applies it.

The tests hold it to that: every cost recommendation is applied for real and the resulting budget re-measured against what it promised.

## The optimizer

| Pass | What it does |
|---|---|
| Draft ladder | Explore takes on the cheap generator; only the keeper runs on the expensive one. |
| Shot reuse | Repeated coverage — same scene, simple motion, no dialogue or vfx — is served from a render you already paid for. |
| Billing fit | Packs shots to vendor minimums and steps, so you stop buying seconds you never use. |
| QC gate | A cheap vision pass kills bad takes before the expensive one runs. |
| Prompt cache | Revision passes re-use context instead of re-sending the bible every time. |
| Provider parallelism | Buys wall clock, not money — and is labelled as such. |

`Planner.measureEfficiency` re-plans the whole picture with each pass disabled and diffs the totals, so the savings figure is auditable rather than asserted.

## The conductor

`Conductor.run` walks the task graph in waves, respecting each tool's `maxConcurrency`, retrying transient failures (and **charging for every attempt**, because vendors do), and writing a ledger of what was actually spent versus estimated, drawn live as a burn-down against the cap. The cap is checked *before* a task starts; hitting it halts the run rather than reporting the overspend afterwards.

- **Dry run** (default) uses `SimulatedAdapter` — deterministic, bills exactly what the plan predicted, needs no keys.
- **Live run** uses `HTTPToolAdapter`, driven entirely by tool-pack data. It refuses to start if a key is missing.

## The cutting room

`Timeline` is a value-type NLE model: tracks, clips, source in/out, transitions, markers, and a take stack per clip. On top of the usual edits it adds the AI-native one — **regenerate this clip**: same slot, same length, different tool or prompt, with the old take kept so `costOfCut` and `costOfUnusedTakes` stay honest. Exports CMX3600 EDL, FCPXML 1.10 and OpenTimelineIO, with provenance in the comments and metadata.

## Scenarios

Producers do not decide in the abstract; they decide between A and B. Snapshot the whole production — picture, strategy, passes, overheads — name it, and compare any two with the deltas that matter: total, per minute, wall clock, shot count. Restore either one.

## Upgrades, new tools, new features

Two extension points, neither of which needs the core to change:

1. **Tool packs** — JSON: `{ "name": …, "tools": [ … ] }`, imported from the Tool Rack. A higher semver upgrades a tool in place and the previous build stays available to roll back to; a lower version is refused so a stale pack can't quietly restore an old rate. Rates are editable in the app, because vendor pricing moves faster than releases. See `Packs/example-vendor-pack.json`.
2. **Modules** — types conforming to `BudgetModule` that append line items and let the engine recompute the roll-ups. Two ship (festival & delivery, marketing package), both off by default.

## Keys

API keys go into the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — this device, never synced), are read only at the moment a vendor is called, and come back everywhere else as a mask. They are never written into the project file, an export or the run log; the HTTP adapter redacts them out of error bodies.

Optionally the planner can be restricted to tools you actually hold keys for — and when that leaves a department unstaffable, you get a gap, not a cheaper number.

---

## A note on the rates

`ToolCatalog` ships plausible dated defaults with vendor-class names rather than pretending to be a live price feed. **Edit them in the Tool Rack, or import a pack, before quoting anyone.** The engine is the product; the numbers are inputs.

## How this was verified

There is no Swift toolchain in the environment this was written in, so the app has not been compiled here. What *was* verified is the part that would otherwise be silently wrong: the engine's arithmetic and control flow were mirrored line-by-line in a throwaway reference implementation and checked against ~260 invariants — shot lists that cover their runtime, line items that sum to the subtotal, tier ordering, every efficiency pass paying for itself, the conductor's cap and retry accounting, blade/ripple/trim/overwrite leaving a valid sequence, shot costs accounting for every dollar of photography, and every advisor recommendation delivering the saving it promises. That mirror is how the key-restriction bug (whole departments vanishing from a budget) was found and fixed.

The XCTest suite in `CinemaComposerProTests/` asserts the same invariants against the real Swift. Expect to fix a small number of compile errors on the first `xcodebuild test` — nothing in this repo has been through a compiler.
