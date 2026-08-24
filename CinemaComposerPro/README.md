# Cinema Composer Pro

**The conductor for an orchestra of AI tools that make feature films.**

A native iOS/iPadOS app (SwiftUI, iOS 17+) that does four jobs the current crop of AI video tools leaves to a spreadsheet:

| | |
|---|---|
| **Producer** | Breaks a runtime down into scenes, shots, dialogue minutes and foley events, then prices all of it — including storage, egress, failed generations you still get billed for, human review hours, and contingency. |
| **Conductor** | Assigns a tool to every job, schedules the task graph under per-vendor concurrency limits, retries what is retryable, and halts the moment spend would pass a hard cap. |
| **Optimizer** | Six efficiency passes, each *measured* by replanning without it, against a "pick the best model and press go" baseline. |
| **Cutting room** | A real NLE — blade, ripple, trim, slip, overwrite, takes — where every clip also knows which tool generated it, from which prompt, for how much. |

Dry runs cost nothing and need no API keys. Live runs need keys, and say so before they spend a cent.

---

## Where things live

```
CinemaComposerPro/
  Models/      FilmSpec, tiers, genres, strategies · AITool, pricing, semver
  Engine/      ToolCatalog · ToolRegistry · BreakdownEngine · Planner
               BudgetEngine · Conductor · ToolAdapter · Timeline · Exporters
  Extensions/  BudgetModule protocol + Festival delivery, Marketing package
  Services/    KeychainStore · ProjectStore · Formatters
  ViewModels/  ProductionViewModel — the single source of truth
  Views/       Producer · Efficiency · Conductor · Cutting room · Rack · Keys
  Packs/       example-vendor-pack.json — the template for wiring a real vendor
CinemaComposerProTests/   engine invariants: breakdown, planner, budget, rack,
                          timeline, conductor
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
- AI share vs human share (on a real feature, supervision is usually the biggest line — the app says so instead of hiding it)
- the runtime cost curve (5 → 150 minutes) and a tier × strategy matrix
- CSV export

## The optimizer

Every pass can be switched off, and the app prices the difference:

| Pass | What it does |
|---|---|
| Draft ladder | Explore takes on the cheap generator; only the keeper runs on the expensive one. |
| Shot reuse | Repeated coverage — same scene, simple motion, no dialogue or vfx — is served from a render you already paid for. |
| Billing fit | Packs shots to vendor minimums and steps, so you stop buying seconds you never use. |
| QC gate | A cheap vision pass kills bad takes before the expensive one runs. |
| Prompt cache | Revision passes re-use context instead of re-sending the bible every time. |
| Provider parallelism | Buys wall clock, not money — and is labelled as such. |

The savings figure is not a marketing number: `Planner.measureEfficiency` re-plans the whole picture with each pass disabled and diffs the totals.

## The conductor

`Conductor.run` walks the task graph in waves, respecting each tool's `maxConcurrency`, retrying transient failures (and **charging for every attempt**, because vendors do), and writing a ledger of what was actually spent versus estimated. The spend cap is checked *before* a task starts; hitting it halts the run rather than reporting the overspend afterwards.

- **Dry run** (default) uses `SimulatedAdapter` — deterministic, bills exactly what the plan predicted, needs no keys.
- **Live run** uses `HTTPToolAdapter`, which is driven entirely by tool-pack data. It refuses to start if a key is missing.

## The cutting room

`Timeline` is a value-type NLE model: tracks, clips, source in/out, transitions, markers, and a take stack per clip. On top of the usual edits it adds the AI-native one — **regenerate this clip**: same slot, same length, different tool or prompt, with the old take kept so `costOfCut` and `costOfUnusedTakes` stay honest. Exports to CMX3600 EDL, FCPXML 1.10 and OpenTimelineIO, with provenance in the comments and metadata.

## Upgrades, new tools, new features

Two extension points, neither of which needs the core to change:

1. **Tool packs** — JSON: `{ "name": …, "tools": [ … ] }`. Import one from the Tool Rack. A higher semver upgrades a tool in place and the previous build stays available to roll back to; a lower version is refused so a stale pack can't quietly restore an old rate. Rates are editable in the app, because vendor pricing moves faster than releases. See `Packs/example-vendor-pack.json`.
2. **Modules** — types conforming to `BudgetModule` that append line items and let the engine recompute the roll-ups. Two ship: festival & delivery, and marketing package. Both are off by default and toggled in the Rack.

## Keys

API keys go into the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — this device, never synced), are read only at the moment a vendor is called, and come back everywhere else as a mask. They are never written into the project file, an export, or the run log; the HTTP adapter redacts them out of error bodies.

Optionally, the planner can be restricted to tools you actually hold keys for, so the budget stops quoting vendors you have no account with.

---

## A note on the rates

`ToolCatalog` ships plausible 2026 defaults with a `ratesAsOf` stamp, using vendor-class names rather than pretending to be a live price feed. **Edit them in the Tool Rack, or import a pack, before quoting anyone.** The engine is the product; the numbers are inputs.

## Also in this repo

**[Cinema Composer Pro](CinemaComposerPro/README.md)** — a separate iOS/iPadOS app target: the conductor for an orchestra of AI tools that make feature films. Producer-grade budgeting by runtime and tier, an efficiency optimizer that measures what each pass saves, a task-graph conductor with a hard spend cap, and an AI-native cutting room that exports EDL/FCPXML/OTIO. Build it from the same `xcodegen generate` (scheme: `CinemaComposerPro`).
