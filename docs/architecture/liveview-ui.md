# LiveView UI Architecture

## Decision

The browser UI lives in a separate Phoenix LiveView app under `web/`.

The core `denario_ex` library remains the source of truth for:

- workflow orchestration
- artifact persistence
- model/provider integrations
- results, literature, paper, and referee generation

The LiveView app is a thin operator shell on top of that core.

## Why This Shape

We explicitly did not build on a desktop-specific agent UI such as OpenSquirrel.
That would have coupled the product surface to a Rust/macOS control plane that
is not designed as an embeddable application framework.

We also did not port Python Streamlit literally. Phoenix LiveView gives us:

- Elixir-native composition
- direct access to the same in-memory and on-disk artifacts as the core app
- built-in live updates without inventing a second client protocol
- a cleaner path to later multi-user or deployment work if we ever need it

## Boundaries

### Core Library

`denario_ex` owns workflow behavior and file persistence.

The UI should talk to the public library API first:

- `DenarioEx.new/1`
- `DenarioEx.set_*`
- `DenarioEx.get_*`
- `DenarioEx.check_idea/2`
- `DenarioEx.referee/2`
- `DenarioEx.research_pilot/3`

Direct reads from `ArtifactRegistry` are acceptable for output links and file
paths, but the UI should not reimplement workflow logic.

### UI Adapter Layer

The UI adapter modules are intentionally small:

- `web/lib/denario_ex_web/projects.ex`
  - normalizes project directories
  - loads snapshots from the core session
  - persists direct artifact edits
  - computes readiness for phase buttons

- `web/lib/denario_ex_web/phase_runner.ex`
  - launches long-running workflow phases
  - converts UI settings into core-library options
  - returns refreshed project snapshots after completion

### LiveView Layer

`web/lib/denario_ex_web_web/live/dashboard_live.ex` owns:

- current project selection
- editable artifact buffers
- transient UI settings
- activity log
- running-phase state

It does not own business logic for the workflow itself.

## Concurrency Model

The current UI uses `Task.Supervisor` for async phase execution.

That is intentional.

It is enough for:

- single-user local operation
- long-running LLM and paper-generation tasks
- live button state and completion notifications

It avoids premature complexity such as:

- database job queues
- multi-node coordination
- retry orchestration outside the core

If we later need durable background jobs, the natural next step is Oban, not a
custom queue.

## File and Output Strategy

The UI is artifact-driven:

- editors write directly to the same `input_files/*.md` artifacts the CLI uses
- phase buttons refresh state from disk after each run
- plots, TeX, PDF, and referee logs are served through a narrow controller that
  only exposes files inside the selected project directory

This keeps the UI and CLI consistent by construction.

## Non-Goals For This Slice

- literal Streamlit parity
- authentication and multi-user accounts
- database-backed project history
- collaborative editing
- advanced run scheduling

Those can come later if the product actually needs them.
