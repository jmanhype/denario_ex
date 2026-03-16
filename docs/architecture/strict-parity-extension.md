# Strict Parity Extension Architecture

Date: March 16, 2026

## Decision

Implement the next DenarioEx parity slice as a library-first extension of the
existing Elixir core instead of porting Python internals verbatim.

## Context

The Python Denario codebase exposes a few remaining parity-facing APIs that sit
on top of persisted session artifacts:

- `get_keywords`
- `enhance_data_description`
- `check_idea_futurehouse`
- `referee`

The old Elixir port had most of the end-to-end workflow, but those features
were still missing and artifact loading logic was spread across `DenarioEx`.

## Chosen Design

### Artifact Registry

`DenarioEx.ArtifactRegistry` is now the single source of truth for persisted
artifact paths and reload behavior. It owns:

- `input_files/data_description.md`
- `input_files/idea.md`
- `input_files/methods.md`
- `input_files/results.md`
- `input_files/literature.md`
- `input_files/referee.md`
- `input_files/keywords.json`
- `input_files/plots/*.png`
- `paper/paper_v4_final.tex`
- `paper/paper_v4_final.pdf`

The session facade still exposes `input_files_dir` and `plots_dir`, but the
path knowledge moved out of `DenarioEx`.

### Session State

`Research` now includes `referee_report`. Keywords remain `map() | list()`, but
they are persisted canonically to `keywords.json` with a small metadata envelope
so `set_all/1` and any later UI can reload them deterministically.

### Workflow Modules

The new feature work lives in small native modules:

- `KeywordWorkflow`
- `DescriptionEnhancementWorkflow`
- `FutureHouseWorkflow`
- `ReviewWorkflow`

`DenarioEx` remains the thin public facade and delegates to those workflows.

### Multimodal LLM Boundary

The client behavior did not split into text and vision paths. Instead,
`AI.complete_messages/4` was added so prebuilt multimodal message payloads can
flow through the existing `LLMClient.complete/2` contract.

### Referee Strategy

Referee review is PDF-first and text-fallback:

1. target `paper/paper_v4_final.pdf`
2. rasterize with `pdftoppm`
3. fall back to `mutool draw`
4. if rasterization is unavailable, review the LaTeX or reconstructed paper text

Rasterization is behind the `PdfRasterizer` behavior so tests and future engines
can swap implementations cleanly.

### FutureHouse Strategy

FutureHouse is implemented as a native HTTP adapter instead of calling the
Python client at runtime. The Elixir adapter mirrors the official client flow:

1. `POST /auth/login`
2. `POST /v0.1/crows`
3. poll `GET /v0.1/trajectories/:id`

## Alternatives Rejected

- Port Python `langgraph` and `cmbagent` internals literally.
  This would have duplicated Python architecture debt and fought the current
  Elixir design.
- Keep keyword and referee outputs mostly in memory.
  That would have broken `set_all/1`, CLI reloads, and later UI work.
- Implement referee as PDF-only.
  Too brittle when compilation or rasterization is unavailable.
- Implement referee as text-only.
  Too far from Python behavior and weaker for multimodal review quality.
- Build a new GUI in the same phase.
  The remaining missing parity is UI-facing, but the stable foundation needed to
  come first.

## Consequences

- Core parity is now behavior-first rather than implementation-first.
- Future UI work has a stable artifact contract to consume.
- Keyword selection, FutureHouse routing, and referee review are testable as
  independent modules.
- The main remaining parity gap is the Python/Streamlit UI surface, not the
  research workflow itself.
