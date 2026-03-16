# DenarioEx

[![CI](https://github.com/jmanhype/denario_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/jmanhype/denario_ex/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)

DenarioEx is a standalone Elixir implementation of the Denario research workflow:
idea generation, method drafting, results execution, literature checking, and
paper generation.

It is built around `ReqLLM` and `LLMDB`, keeps project artifacts on disk, and
can run either as a real OpenAI-backed workflow or as a fully offline demo.

## What It Covers

- project/session lifecycle with persisted `input_files/`
- fast and `cmbagent`-style idea and method generation
- `get_results/2` with planning, code generation, execution, retries, and plot harvesting
- literature checking via Semantic Scholar with OpenAlex fallback
- LaTeX paper generation with optional bibliography and PDF compilation

## Quickstart

```bash
mix deps.get
mix test
mix escript.build
```

## CLI

The standalone repo now ships with an escript entrypoint:

```bash
./denario_ex offline-demo --project-dir /tmp/denario_ex_demo
```

For a real run:

```bash
./denario_ex research-pilot \
  --project-dir /tmp/denario_ex_full \
  --data-description-file ./project_input.md \
  --mode fast \
  --llm openai:gpt-4.1-mini \
  --literature
```

`research-pilot` is the one-call compatibility workflow. It loads the data
description, runs idea generation, method generation, results, optional
literature checking, and paper generation in sequence.

If you are not running inside an activated virtualenv, point the results
executor at a known-good interpreter:

```bash
DENARIO_EX_PYTHON=/path/to/venv/bin/python ./denario_ex research-pilot ...
```

## Offline Demo

The fastest way to see the full workflow without API keys or network access is:

```bash
mix run examples/offline_demo.exs
```

That script runs a deterministic end-to-end flow with fake LLM, execution, and
literature clients, then writes a complete demo project directory containing:

- `input_files/data_description.md`
- `input_files/idea.md`
- `input_files/methods.md`
- `input_files/results.md`
- `input_files/literature.md`
- `input_files/plots/anomaly_scores.png`
- `paper/paper_v4_final.tex`

To control the output directory:

```bash
DENARIO_EX_DEMO_DIR=/tmp/denario_ex_demo mix run examples/offline_demo.exs
```

Or through the CLI:

```bash
./denario_ex offline-demo --project-dir /tmp/denario_ex_demo
```

## Real OpenAI Workflow

For a real run, export your OpenAI key and use the library directly:

```bash
export OPENAI_API_KEY=...
iex -S mix
```

```elixir
alias DenarioEx

{:ok, denario} =
  DenarioEx.new(project_dir: "/tmp/denario_ex_full", clear_project_dir: true)

{:ok, denario} =
  DenarioEx.set_data_description(
    denario,
    "Generate a tiny synthetic anomaly-score dataset, summarize it, and write a short paper."
  )

{:ok, denario} =
  DenarioEx.get_idea(
    denario,
    mode: :cmbagent,
    planner_model: "openai:gpt-4.1-mini"
  )

{:ok, denario} =
  DenarioEx.get_method(
    denario,
    mode: :cmbagent,
    planner_model: "openai:gpt-4.1-mini"
  )

{:ok, denario} =
  DenarioEx.get_results(
    denario,
    planner_model: "openai:gpt-4.1-mini",
    engineer_model: "openai:gpt-4.1-mini"
  )

{:ok, denario} = DenarioEx.check_idea(denario, llm: "openai:gpt-4.1-mini")
{:ok, denario} = DenarioEx.get_paper(denario, llm: "openai:gpt-4.1-mini", compile: false)
```

## Credentials

DenarioEx reads these environment variables:

- OpenAI: `OPENAI_API_KEY`
- Gemini: `GOOGLE_API_KEY` or `GEMINI_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`
- Perplexity: `PERPLEXITY_API_KEY`
- Semantic Scholar: `SEMANTIC_SCHOLAR_KEY`, `SEMANTIC_SCHOLAR_API_KEY`, or `S2_API_KEY`

`check_idea/2` uses Semantic Scholar first and falls back to OpenAlex when no
Semantic Scholar key is present or the public endpoint is rate-limited.

## Releases

GitHub releases are cut from tags:

```bash
git tag v0.1.2
git push origin v0.1.2
```

The release workflow runs the test suite and publishes a GitHub release with
generated notes.

## Parity Status

The current parity audit lives in [PARITY.md](PARITY.md).

Short version:

- core research workflow: effectively ported
- compatibility surface: mostly ported, with a few Python-only branches still missing
- Python Streamlit app: not ported

## Temporary `req_llm` Pin

This repo is temporarily pinned to a Git commit of `req_llm` instead of the
latest Hex release.

- Current pin: `jmanhype/req_llm@ee00b4553cd6823b48c1045b825565855a77a93b`
- Upstream fix: <https://github.com/agentjido/req_llm/pull/506>

This exists because `req_llm` `1.7.1` still injects `:max_tokens` for some
OpenAI reasoning/object calls, which causes noisy
`Renamed :max_tokens to :max_completion_tokens` warnings.

Once that fix lands in Hex, replace the Git dependency in `mix.exs` with the
published version and refresh `mix.lock`.

## Source Lineage

This repository started as an extraction from the Elixir port previously
developed in `AstroPilot-AI/Denario`, and now continues independently as the
standalone `denario_ex` project.
