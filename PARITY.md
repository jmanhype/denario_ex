# Parity Status

As of March 16, 2026, DenarioEx is close to replacement parity for the main
research workflow, but it is not literal `1:1` parity with the Python Denario
codebase.

Working estimate:

- main workflow parity: high
- public API parity: partial
- overall replacement parity: roughly `85-90%` for normal research-paper usage

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
| `show_keywords` | `show_keywords/1` | ported with differences | Elixir formats markdown output but does not do notebook-aware rendering. |
| `enhance_data_description` | none | missing | Python `cmbagent.preprocess_task` path is not ported. |
| `get_idea` | `get_idea/2` | ported | Supports fast and `cmbagent` modes. |
| `get_idea_cmagent` | `get_idea_cmbagent/2` | ported with differences | Elixir uses an Elixir-native planning loop, not Python `cmbagent`. |
| `get_idea_fast` | `get_idea_fast/2` | ported | |
| `check_idea` | `check_idea/2` | ported with differences | Elixir supports Semantic Scholar mode plus OpenAlex fallback. |
| `check_idea_futurehouse` | none | missing | FutureHouse integration not ported. |
| `check_idea_semantic_scholar` | `check_idea/2` | ported with differences | Wrapped behind `check_idea/2` with improved fallback behavior. |
| `get_method` | `get_method/2` | ported | Supports fast and `cmbagent` modes. |
| `get_method_cmbagent` | `get_method_cmbagent/2` | ported with differences | Elixir uses an Elixir-native planning loop. |
| `get_method_fast` | `get_method_fast/2` | ported | |
| `get_results` | `get_results/2` | ported with differences | Same high-level workflow, different implementation architecture. |
| `get_keywords` | none | missing | Keywords are generated during paper writing, but standalone keyword API is not exposed. |
| `get_paper` | `get_paper/2` | ported | Journal presets and optional compile are supported. |
| `referee` | none | missing | No paper-review workflow yet. |
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

## Remaining High-Value Gaps

If stricter parity is needed, the next features to port are:

1. `get_keywords`
2. `referee`
3. `enhance_data_description`
4. `check_idea_futurehouse`
5. Python-style UI layer, if the Streamlit surface still matters
