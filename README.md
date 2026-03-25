# DenarioEx

[![CI](https://github.com/jmanhype/denario_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/jmanhype/denario_ex/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)

Elixir port of the Denario research workflow. Takes a data description, generates a research idea, drafts methods, executes code to produce results, checks literature, and generates a LaTeX paper.

**Status:** v0.2.1. Core research pipeline works end-to-end with OpenAI. 90-95% parity with the Python Denario codebase (see [PARITY.md](PARITY.md) for the full mapping). The Phoenix LiveView web UI is functional but early.

## Project structure

The repo has 2 OTP applications:

```
lib/denario_ex/          Core library (31 modules)
web/                     Phoenix LiveView research workspace (separate app)
test/                    16 test files for the core library
examples/                Offline demo script
priv/keywords/           UNESCO, AAS, AAAI keyword taxonomies
priv/latex/              Journal style files (AASTeX, ICML, NeurIPS, JHEP, PASJ)
```

### Core modules (lib/denario_ex/)

| Module | Purpose |
|---|---|
| `research.ex` | Main orchestrator: `new/1`, `set_data_description/2`, `get_idea/2`, `get_method/2`, `get_results/2`, `check_idea/2`, `get_paper/2` |
| `cmbagent_loop.ex` | Multi-agent planning loop (Elixir-native, not Python cmbagent) |
| `results_workflow.ex` | Code planning, generation, execution, retry, plot harvesting |
| `literature_workflow.ex` | Semantic Scholar search with OpenAlex fallback |
| `paper_workflow.ex` | LaTeX generation with journal presets and optional PDF compilation |
| `review_workflow.ex` | Referee pass with PDF rasterization fallback |
| `keyword_workflow.ex` | Keyword extraction (UNESCO, AAS, AAAI taxonomies) |
| `description_enhancement_workflow.ex` | LLM-based data description rewriting |
| `future_house.ex`, `future_house_client.ex` | FutureHouse/Edison API integration |
| `semantic_scholar.ex`, `semantic_scholar_client.ex` | Semantic Scholar API |
| `open_alex.ex` | OpenAlex fallback for literature search |
| `code_executor.ex`, `python_executor.ex` | Sandboxed Python code execution |
| `pdf_rasterizer.ex`, `system_pdf_rasterizer.ex` | PDF-to-image for referee review |
| `llm.ex`, `llm_client.ex`, `req_llm_client.ex` | LLM abstraction over ReqLLM |
| `key_manager.ex` | API key rotation and management |
| `artifact_registry.ex` | On-disk artifact tracking |
| `cli.ex` | Escript entrypoint |
| `offline_demo.ex` | Deterministic demo with fake clients |
| `prompt_templates.ex`, `workflow_prompts.ex` | LLM prompt text |
| `ai.ex`, `text.ex`, `progress.ex` | Utilities |

### Web UI (web/)

Phoenix LiveView app. Single-page dashboard at `/` showing project status, workflow progress, artifact editing, and run history. `/artifacts` serves generated files (TeX, PDF, plots).

6 phase states: `missing`, `ready`, `running`, `blocked`, `review_needed`, `done`.

## Dependencies

- Elixir 1.18+
- `req` ~> 0.5.17 (HTTP client)
- `llm_db` ~> 2026.3 (model metadata)
- `req_llm` (pinned to a Git commit -- see note below)

## Quick start

```bash
mix deps.get
mix test
mix escript.build
```

### Offline demo (no API keys needed)

```bash
mix run examples/offline_demo.exs
```

Runs a deterministic workflow with fake LLM and literature clients. Writes a complete project directory with idea, methods, results, literature review, a plot, and a LaTeX paper.

```bash
# Or via the CLI:
./denario_ex offline-demo --project-dir /tmp/denario_ex_demo
```

### Real workflow

```bash
export OPENAI_API_KEY=...

./denario_ex research-pilot \
  --project-dir /tmp/denario_ex_full \
  --data-description-file ./project_input.md \
  --mode fast \
  --llm openai:gpt-4.1-mini \
  --literature
```

`research-pilot` runs the full sequence: idea generation, method generation, results execution, optional literature check, paper generation.

### Programmatic usage

```elixir
{:ok, d} = DenarioEx.new(project_dir: "/tmp/demo", clear_project_dir: true)
{:ok, d} = DenarioEx.set_data_description(d, "Generate a synthetic dataset and write a paper.")
{:ok, d} = DenarioEx.get_idea(d, mode: :cmbagent, planner_model: "openai:gpt-4.1-mini")
{:ok, d} = DenarioEx.get_method(d, mode: :cmbagent, planner_model: "openai:gpt-4.1-mini")
{:ok, d} = DenarioEx.get_results(d, planner_model: "openai:gpt-4.1-mini", engineer_model: "openai:gpt-4.1-mini")
{:ok, d} = DenarioEx.check_idea(d, llm: "openai:gpt-4.1-mini")
{:ok, d} = DenarioEx.get_paper(d, llm: "openai:gpt-4.1-mini", compile: false)
```

### Web UI

```bash
cd web && mix deps.get && mix phx.server
```

Open http://localhost:4000.

## API credentials

| Variable | Service |
|---|---|
| `OPENAI_API_KEY` | OpenAI |
| `GOOGLE_API_KEY` or `GEMINI_API_KEY` | Gemini |
| `ANTHROPIC_API_KEY` | Anthropic |
| `PERPLEXITY_API_KEY` | Perplexity |
| `SEMANTIC_SCHOLAR_KEY` or `S2_API_KEY` | Semantic Scholar |
| `FUTURE_HOUSE_API_KEY` | FutureHouse/Edison |

Literature search uses Semantic Scholar first, falls back to OpenAlex when no key is present or the public endpoint is rate-limited.

For Python code execution, set `DENARIO_EX_PYTHON` to a virtualenv interpreter path if needed.

## Temporary req_llm pin

`req_llm` is pinned to a Git commit (`jmanhype/req_llm@ee00b45`) instead of the Hex release. This works around a `max_tokens` vs `max_completion_tokens` naming issue in `req_llm` 1.7.1 with OpenAI reasoning models. See [upstream PR #506](https://github.com/agentjido/req_llm/pull/506). Replace with the Hex version once that fix ships.

## Design decisions

**Elixir-native planning loop, not Python cmbagent.** The `cmbagent_loop.ex` module reimplements the multi-agent planning pattern in Elixir rather than calling out to the Python cmbagent library. This removes the Python runtime dependency for the core workflow.

**ReqLLM over raw HTTP.** Using `req_llm` as the LLM client layer means model routing, streaming, and provider differences are handled by the library rather than custom code. The tradeoff is the temporary Git pin mentioned above.

**Separate web app.** The Phoenix LiveView UI is a separate OTP application under `web/` rather than being mixed into the core library. This keeps the escript and library usable without Phoenix as a dependency.

**PDF rasterization for referee review.** The referee workflow converts generated PDFs to images for LLM review rather than parsing LaTeX directly. Falls back to raw LaTeX text when no PDF renderer is available.

## Known limitations

- The Python code executor runs generated code in a subprocess. There is no sandboxing beyond the OS process boundary.
- Literature search depends on Semantic Scholar's public API, which has aggressive rate limits without an API key.
- PDF compilation requires a LaTeX distribution (texlive/mactex) installed on the host.
- The web UI is a single LiveView page. There is no multi-user support or authentication.
- Parity with the Python Denario is approximately 90-95%. See [PARITY.md](PARITY.md) for the specific function-by-function mapping.

## Releases

```bash
git tag v0.2.1
git push origin v0.2.1
```

The release workflow runs tests and publishes a GitHub release.

## Source lineage

Extracted from the Elixir port in `AstroPilot-AI/Denario`. Now maintained independently.

## License

GPL-3.0
