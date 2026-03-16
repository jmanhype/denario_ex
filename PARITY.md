# Parity Status

As of March 16, 2026, DenarioEx is close to replacement parity for the main
research workflow, but it is not literal `1:1` parity with the Python Denario
codebase.

Working estimate:

- main workflow parity: very high
- public API parity: high
- overall replacement parity: roughly `90-95%` for normal research-paper usage

## Status Legend

- `ported`: equivalent public surface exists in Elixir
- `ported with differences`: feature exists, but behavior or implementation differs
- `missing`: no Elixir counterpart yet

## Python API Mapping

| Python Denario | Elixir DenarioEx | Status | Notes |
| --- | --- | --- | --- |
| `__init__` | `new/1` | ported | Session/project lifecycle exists. |
| `reset` | `reset/1` | ported with differences | Elixir clears in-memory research state and preserves on-disk artifacts. |
| `set_data_description` | `set_data_description/2` | ported | |
| `set_idea` | `set_idea/2` | ported | |
| `set_method` | `set_method/2` | ported | |
| `set_results` | `set_results/2` | ported | |
| `set_plots` | `set_plots/2` | ported with differences | Elixir is file-path based; Python also accepts `PIL.Image` objects. |
| `set_all` | `set_all/1` | ported | Reloads persisted project artifacts into the session. |
| `show_data_description` | `show_data_description/1` | ported | Elixir returns text instead of printing. |
| `show_idea` | `show_idea/1` | ported | Elixir returns text instead of printing. |
| `show_method` | `show_method/1` | ported | Elixir returns text instead of printing. |
| `show_results` | `show_results/1` | ported | Elixir returns text instead of printing. |
| `show_keywords` | `show_keywords/1` | ported with differences | Elixir formats markdown output and reloads persisted `keywords.json`, but does not do notebook-aware rendering. |
| `enhance_data_description` | `enhance_data_description/2` | ported with differences | Elixir uses an LLM-native rewrite workflow instead of Python `cmbagent.preprocess_task`. |
| `get_idea` | `get_idea/2` | ported | Supports fast and `cmbagent` modes. |
| `get_idea_cmagent` | `get_idea_cmbagent/2` | ported with differences | Elixir uses an Elixir-native planning loop, not Python `cmbagent`. |
| `get_idea_fast` | `get_idea_fast/2` | ported | |
| `check_idea` | `check_idea/2` | ported with differences | Elixir supports both Semantic Scholar and FutureHouse modes, plus OpenAlex fallback for public literature search. |
| `check_idea_futurehouse` | `check_idea_futurehouse/2` | ported with differences | Native HTTP adapter replaces the Python FutureHouse client. |
| `check_idea_semantic_scholar` | `check_idea/2` | ported with differences | Wrapped behind `check_idea/2` with improved fallback behavior. |
| `get_method` | `get_method/2` | ported | Supports fast and `cmbagent` modes. |
| `get_method_cmbagent` | `get_method_cmbagent/2` | ported with differences | Elixir uses an Elixir-native planning loop. |
| `get_method_fast` | `get_method_fast/2` | ported | |
| `get_results` | `get_results/2` | ported with differences | Same high-level workflow, different implementation architecture. |
| `get_keywords` | `get_keywords/3` | ported with differences | Elixir persists canonical `keywords.json` and supports `:unesco`, `:aas`, and `:aaai`. |
| `get_paper` | `get_paper/2` | ported | Journal presets and optional compile are supported. |
| `referee` | `referee/2` | ported with differences | Elixir uses PDF-first review with rasterizer fallback, then falls back to LaTeX/source text. |
| `research_pilot` | `research_pilot/3` | ported with differences | Elixir supports nested stage opts and optional literature step. |

## Product-Level Parity

| Python surface | Elixir status | Notes |
| --- | --- | --- |
| `denario run` Streamlit app | missing | No Streamlit-equivalent UI in the standalone Elixir repo. |
| standalone CLI | ported with differences | Elixir provides `denario_ex research-pilot` and `denario_ex offline-demo` escript commands. |
| offline reproducible demo | ported | `mix run examples/offline_demo.exs` and `./denario_ex offline-demo` both work. |

## Architectural Differences

These are intentional differences, not parity bugs:

- Elixir replaces Python `langgraph` and `cmbagent` orchestration with native
  modules like `DenarioEx.CMBAgentLoop`.
- Elixir uses `ReqLLM` and `LLMDB` as the model/client substrate.
- Elixir literature checking adds an OpenAlex fallback that the Python version
  does not have in the main API.
- Elixir persists keyword and referee artifacts explicitly so `set_all/1`,
  future CLIs, and any future GUI can reload session state deterministically.

## Remaining High-Value Gaps

If stricter parity is needed, the next features to port are:

1. Python-style UI layer, if the Streamlit surface still matters
2. any notebook-specific display behavior you still care about
3. deeper behavioral matching for Python `preprocess_task`, if exact preprocessing parity becomes important
