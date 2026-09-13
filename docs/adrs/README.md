# Architecture Decision Records

Every ADR follows the same template — **Title · Status · Context · Decision ·
Consequences** (with **Positive** and **Negative** subheadings):

- **Title** — the decision's one-line name (the file's `# N. ...` heading).
- **Status** — `Proposed`, `Accepted`, `Rejected`, or `Superseded by ADR-XXXX`.
- **Context** — the situation and constraints that required the decision.
- **Decision** — the decision made, the options rejected, and why.
- **Consequences** — outcomes under **Positive** / **Negative** headings.

| # | Decision | Status | Version | Tasks |
|---|---|---|---|---|
| [0001](0001-leveldata-id-contract.md) | `LevelData.id` is zero-based, `id + 1` in display | Accepted | 1.1.0 | T-19, T-02 |
| [0002](0002-fixing-boss-level-formula.md) | Boss formula `% 15 == 14`, ships in 2.0.0 | Accepted | 2.0.0 | T-01, T-22 |
| [0003](0003-making-reward-system-injectable.md) | Reward system via Strategy + Constructor Injection; pity and `executeAndPersist` | Accepted | 2.0.0 / 2.1.0 | T-04, T-12, T-13, T-14 |
| [0004](0004-saga-progress-extensibility.md) | `SagaProgress.extra` + `saveGlobalSeed`; `spentStars` + `starsByMode` | Accepted | 1.1.0 / 2.0.0 / 2.1.0 | T-03, T-09, T-16, T-18 |
| [0005](0005-promoting-gate-to-progress-barrier.md) | Gate = progress barrier (3 hooks) | Accepted | 2.0.0 | T-06 |
| [0006](0006-builder-context-and-level-aligned-decor.md) | `SagaChunkContext` + `atLevel` decor | Accepted | 1.1.0 | T-05, T-10, T-15 |
| [0007](0007-host-defined-biomes.md) | `SagaMapConfig.biomeIds` + theme asset hook | Accepted | 2.0.0 | T-11 |
| [0008](0008-decoupling-flutter-svg-dependency.md) | Drop the `flutter_svg` dependency | Accepted | 2.0.0 | T-20 |
| [0009](0009-client-side-reward-trust-boundary.md) | A client-side rolled reward is advisory | Accepted | 2.0.0 | T-14 |
| [0010](0010-keeping-equatable-and-fast-noise-dependencies.md) | Keep `equatable` + `fast_noise` | Accepted | 2.0.0 | T-25 |

## Status flow

Every ADR starts `Proposed`. It becomes `Accepted` once the implementing task
merges, `Rejected` if abandoned, or `Superseded by ADR-XXXX` if replaced by a
later decision. The relevant ADRs' statuses must be updated before a version
ships (see `../../.old/docs/reports/04-surumleme-ve-gecis-plani.md` §7).

## New ADR

Open a new file named `NNNN-short-title.md` inside `docs/adrs/`, using one more
than the current highest ADR number. Fill it out following the template above
(**Title · Status · Context · Decision · Consequences**) and add the new row
to the table in `README.md`.
