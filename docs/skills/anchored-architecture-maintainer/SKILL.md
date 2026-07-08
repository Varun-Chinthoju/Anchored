---
name: anchored-architecture-maintainer
description: Use when making a major update in the Anchored repo that changes architecture, runtime composition, engine behavior, persistence, permissions/privacy flow, module ownership, or the V2.6 implementation plan. Updates the canonical architecture doc so future agents do not need to rediscover repo structure from scratch.
---

# Anchored Architecture Maintainer

This is a repo-specific maintenance skill. Use it before finishing any major update in Anchored.

## Required inputs

Read these first:

- `AGENTS.md`
- `docs/architecture/anchored-architecture.md`
- the files you changed
- `docs/ideas/anchored-v2.6-plan.md` if the work touches the V2.6 context/history/privacy effort

## What counts as a major update

Run this skill when the change does any of the following:

- adds, removes, or materially refactors a runtime module
- changes `AppDelegate` composition or dependency wiring
- changes `FocusEngine` state flow, timers, notifications, or delegate semantics
- changes browser/native context collection or browser strategy ownership
- changes database schema, storage ownership, analytics reconstruction, or migration behavior
- changes settings, permission gates, privacy controls, or history retention behavior
- adds a new plan-driven architectural seam in `docs/ideas/anchored-v2.6-plan.md`

If the answer is unclear, treat it as major and update the doc.

## Procedure

1. Inspect the current code, not just the plan.
2. Update `docs/architecture/anchored-architecture.md` so it reflects the shipped architecture after your change.
3. Keep the following sections accurate if they were affected:
   - `Current State Snapshot`
   - `Runtime Composition`
   - `Core Modules`
   - `High-Value Invariants`
   - `Current Weak Spots`
   - `V2.6 Impact Surface`
   - `Where To Start By Task Type`
4. Replace stale statements instead of only appending new notes.
5. Add exact file paths for any new seam future agents must read.
6. If the implementation diverges from `docs/ideas/anchored-v2.6-plan.md`, note the new reality in the architecture doc and update the plan if the task requires it.
7. Before finishing, verify that a new agent could answer these without broad repo search:
   - Where is the composition root?
   - What is the main runtime flow?
   - Where does focus classification happen?
   - Where does persistence live?
   - Which files change for this feature area?

## Output standard

The architecture doc should:

- describe present tense, current code
- call out invariants and ownership boundaries
- identify the files to read first
- stay concise enough to scan quickly

## Completion gate

A major update is not complete until `docs/architecture/anchored-architecture.md` has been reviewed and updated for the change if needed.
