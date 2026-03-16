# DenarioExUI

`web/` is the Phoenix LiveView control room for the standalone `denario_ex`
library. It does not own the research workflow itself. It opens project
directories, edits artifact files, launches workflow phases, and links to the
generated plots and paper outputs.

## Run

```bash
mix deps.get
mix test
mix phx.server
```

Then open [`localhost:4000`](http://localhost:4000).

## Scope

Current UI slice:

- open or create a Denario project directory
- edit persisted research artifacts in place
- launch workflow phases asynchronously from the browser
- inspect generated plots, TeX, PDF, and referee logs

## Architecture

- `../lib/denario_ex.ex` remains the source of truth for the workflow
- `web/lib/denario_ex_web/projects.ex` adapts project directories into UI state
- `web/lib/denario_ex_web/phase_runner.ex` runs long workflow phases under `Task.Supervisor`
- `web/lib/denario_ex_web_web/live/dashboard_live.ex` owns the LiveView control room

For the design rationale, see [`../docs/architecture/liveview-ui.md`](../docs/architecture/liveview-ui.md).
