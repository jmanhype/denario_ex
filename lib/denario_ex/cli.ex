defmodule DenarioEx.CLI do
  @moduledoc false

  alias DenarioEx.OfflineDemo

  def main(argv) do
    System.halt(run(argv))
  end

  def run(argv) do
    case argv do
      [] ->
        print_help()
        0

      ["help" | _rest] ->
        print_help()
        0

      ["offline-demo" | rest] ->
        run_offline_demo(rest)

      ["research-pilot" | rest] ->
        run_research_pilot(rest)

      [command | _rest] ->
        IO.puts(:stderr, "Unknown command: #{command}\n")
        print_help()
        1
    end
  end

  defp run_offline_demo(argv) do
    case OptionParser.parse(argv,
           strict: [project_dir: :string, compile: :boolean, quiet: :boolean]
         ) do
      {opts, [], []} ->
        demo_opts =
          []
          |> maybe_put(:project_dir, opts[:project_dir])
          |> Keyword.put(:compile, Keyword.get(opts, :compile, false))
          |> Keyword.put(:print, !Keyword.get(opts, :quiet, false))

        case OfflineDemo.run(demo_opts) do
          {:ok, _denario} -> 0
          {:error, reason} -> cli_error(reason)
        end

      {_opts, _args, invalid} ->
        invalid_options("offline-demo", invalid)
    end
  end

  defp run_research_pilot(argv) do
    strict = [
      project_dir: :string,
      clear_project_dir: :boolean,
      data_description: :string,
      data_description_file: :string,
      mode: :string,
      llm: :string,
      planner_model: :string,
      plan_reviewer_model: :string,
      idea_maker_model: :string,
      idea_hater_model: :string,
      method_generator_model: :string,
      engineer_model: :string,
      researcher_model: :string,
      formatter_model: :string,
      paper_model: :string,
      literature_model: :string,
      writer: :string,
      journal: :string,
      compile: :boolean,
      literature: :boolean
    ]

    case OptionParser.parse(argv, strict: strict) do
      {opts, [], []} ->
        with {:ok, mode} <- normalize_mode(Keyword.get(opts, :mode, "fast")),
             {:ok, data_description} <- resolve_data_description(opts),
             {:ok, denario} <-
               DenarioEx.new(
                 project_dir: Keyword.get(opts, :project_dir, Path.join(File.cwd!(), "project")),
                 clear_project_dir: Keyword.get(opts, :clear_project_dir, false)
               ),
             {:ok, denario} <-
               DenarioEx.research_pilot(
                 denario,
                 data_description,
                 idea: idea_opts(opts, mode),
                 method: method_opts(opts, mode),
                 results: results_opts(opts),
                 literature: literature_opts(opts),
                 paper: paper_opts(opts)
               ) do
          IO.puts(project_summary(denario))
          0
        else
          {:error, reason} -> cli_error(reason)
        end

      {_opts, _args, invalid} ->
        invalid_options("research-pilot", invalid)
    end
  end

  defp idea_opts(opts, :fast) do
    [mode: :fast, llm: default_model(opts)]
  end

  defp idea_opts(opts, :cmbagent) do
    [
      mode: :cmbagent,
      idea_maker_model: Keyword.get(opts, :idea_maker_model, default_model(opts)),
      idea_hater_model: Keyword.get(opts, :idea_hater_model, default_model(opts)),
      planner_model: Keyword.get(opts, :planner_model, default_model(opts)),
      plan_reviewer_model: Keyword.get(opts, :plan_reviewer_model, default_model(opts)),
      formatter_model: Keyword.get(opts, :formatter_model, default_model(opts))
    ]
  end

  defp method_opts(opts, :fast) do
    [mode: :fast, llm: default_model(opts)]
  end

  defp method_opts(opts, :cmbagent) do
    [
      mode: :cmbagent,
      method_generator_model: Keyword.get(opts, :method_generator_model, default_model(opts)),
      planner_model: Keyword.get(opts, :planner_model, default_model(opts)),
      plan_reviewer_model: Keyword.get(opts, :plan_reviewer_model, default_model(opts)),
      formatter_model: Keyword.get(opts, :formatter_model, default_model(opts))
    ]
  end

  defp results_opts(opts) do
    [
      planner_model: Keyword.get(opts, :planner_model, default_model(opts)),
      plan_reviewer_model: Keyword.get(opts, :plan_reviewer_model, default_model(opts)),
      engineer_model: Keyword.get(opts, :engineer_model, default_model(opts)),
      researcher_model: Keyword.get(opts, :researcher_model, default_model(opts)),
      formatter_model: Keyword.get(opts, :formatter_model, default_model(opts))
    ]
  end

  defp literature_opts(opts) do
    if Keyword.get(opts, :literature, false) do
      [llm: Keyword.get(opts, :literature_model, default_model(opts))]
    else
      :skip
    end
  end

  defp paper_opts(opts) do
    [
      llm: Keyword.get(opts, :paper_model, default_model(opts)),
      writer: Keyword.get(opts, :writer, "scientist"),
      journal: normalize_journal(Keyword.get(opts, :journal, "none")),
      compile: Keyword.get(opts, :compile, false)
    ]
  end

  defp default_model(opts) do
    Keyword.get(opts, :llm, "openai:gpt-4.1-mini")
  end

  defp normalize_mode(mode) when mode in ["fast", "cmbagent"] do
    {:ok, String.to_atom(mode)}
  end

  defp normalize_mode(mode) when mode in [:fast, :cmbagent], do: {:ok, mode}
  defp normalize_mode(mode), do: {:error, {:invalid_mode, mode}}

  defp normalize_journal(journal)
       when journal in [:none, :aas, :aps, :icml, :jhep, :neurips, :pasj],
       do: journal

  defp normalize_journal(journal) when is_binary(journal) do
    case String.downcase(journal) do
      "none" -> :none
      "aas" -> :aas
      "aps" -> :aps
      "icml" -> :icml
      "jhep" -> :jhep
      "neurips" -> :neurips
      "pasj" -> :pasj
      _ -> :none
    end
  end

  defp resolve_data_description(opts) do
    case {opts[:data_description], opts[:data_description_file]} do
      {text, nil} when is_binary(text) ->
        {:ok, text}

      {nil, nil} ->
        {:ok, nil}

      {nil, file} when is_binary(file) ->
        case File.read(file) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, {:data_description_file_error, file, reason}}
        end

      {_text, _file} ->
        {:error, :conflicting_data_description_inputs}
    end
  end

  defp project_summary(denario) do
    files =
      [
        Path.join(denario.input_files_dir, "data_description.md"),
        Path.join(denario.input_files_dir, "idea.md"),
        Path.join(denario.input_files_dir, "methods.md"),
        Path.join(denario.input_files_dir, "results.md"),
        Path.join(denario.input_files_dir, "literature.md"),
        denario.research.paper_tex_path,
        denario.research.paper_pdf_path
      ]
      |> Enum.filter(&(is_binary(&1) and File.exists?(&1)))

    """
    Research pilot completed.

    Project directory: #{denario.project_dir}
    Idea: #{excerpt(denario.research.idea)}
    Results: #{excerpt(denario.research.results)}

    Generated files:
    #{Enum.map_join(files, "\n", &"- #{&1}")}
    """
  end

  defp excerpt(text) do
    text
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 120)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp invalid_options(command, invalid) do
    IO.puts(:stderr, "Invalid options for #{command}: #{inspect(invalid)}")
    1
  end

  defp cli_error(:conflicting_data_description_inputs) do
    IO.puts(:stderr, "Pass either --data-description or --data-description-file, not both.")
    1
  end

  defp cli_error({:data_description_file_error, file, reason}) do
    IO.puts(:stderr, "Could not read #{file}: #{:file.format_error(reason)}")
    1
  end

  defp cli_error({:invalid_mode, mode}) do
    IO.puts(:stderr, "Unsupported mode #{inspect(mode)}. Use fast or cmbagent.")
    1
  end

  defp cli_error(reason) do
    IO.puts(:stderr, "Command failed: #{inspect(reason)}")
    1
  end

  defp print_help do
    IO.puts("""
    denario_ex research-pilot [options]
    denario_ex offline-demo [options]

    Commands:
      research-pilot  Run the one-shot workflow from data description to paper draft.
      offline-demo    Run the deterministic no-network demo workflow.

    Research pilot options:
      --project-dir PATH
      --clear-project-dir
      --data-description TEXT
      --data-description-file FILE
      --mode fast|cmbagent
      --llm MODEL
      --planner-model MODEL
      --plan-reviewer-model MODEL
      --engineer-model MODEL
      --researcher-model MODEL
      --formatter-model MODEL
      --paper-model MODEL
      --literature-model MODEL
      --writer ROLE
      --journal none|aas|aps|icml|jhep|neurips|pasj
      --literature
      --compile

    Offline demo options:
      --project-dir PATH
      --compile
      --quiet
    """)
  end
end
