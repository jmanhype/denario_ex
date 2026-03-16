defmodule DenarioEx.ArtifactRegistry do
  @moduledoc false

  alias DenarioEx.Research

  @input_files "input_files"
  @plots_folder "plots"
  @paper_folder "paper"
  @referee_output "referee_output"

  @text_artifacts %{
    data_description: {"input_files", "data_description.md"},
    idea: {"input_files", "idea.md"},
    methodology: {"input_files", "methods.md"},
    results: {"input_files", "results.md"},
    literature: {"input_files", "literature.md"},
    referee_report: {"input_files", "referee.md"}
  }

  @path_artifacts %{
    keywords: {"input_files", "keywords.json"},
    paper_tex: {"paper", "paper_v4_final.tex"},
    paper_pdf: {"paper", "paper_v4_final.pdf"}
  }

  @spec input_files_dir(String.t()) :: String.t()
  def input_files_dir(project_dir), do: Path.join(project_dir, @input_files)

  @spec plots_dir(String.t()) :: String.t()
  def plots_dir(project_dir), do: Path.join(input_files_dir(project_dir), @plots_folder)

  @spec paper_dir(String.t()) :: String.t()
  def paper_dir(project_dir), do: Path.join(project_dir, @paper_folder)

  @spec referee_output_dir(String.t()) :: String.t()
  def referee_output_dir(project_dir), do: Path.join(project_dir, @referee_output)

  @spec path(String.t(), atom()) :: String.t()
  def path(project_dir, artifact) when is_atom(artifact) do
    case Map.get(@text_artifacts, artifact) || Map.get(@path_artifacts, artifact) do
      {folder, filename} -> Path.join(Path.join(project_dir, folder), filename)
      nil -> raise ArgumentError, "unknown artifact: #{inspect(artifact)}"
    end
  end

  @spec ensure_project_dirs(String.t()) :: :ok
  def ensure_project_dirs(project_dir) do
    File.mkdir_p!(plots_dir(project_dir))
    File.mkdir_p!(paper_dir(project_dir))
    :ok
  end

  @spec write_text(String.t(), atom(), String.t()) :: :ok
  def write_text(project_dir, artifact, content) when is_binary(content) do
    destination = path(project_dir, artifact)
    File.mkdir_p!(Path.dirname(destination))
    File.write!(destination, content)
    :ok
  end

  @spec persist_keywords(String.t(), map() | list(), keyword()) :: :ok
  def persist_keywords(project_dir, keywords, opts \\ [])
      when is_map(keywords) or is_list(keywords) do
    payload = %{
      version: 1,
      kw_type: normalize_kw_type(Keyword.get(opts, :kw_type, infer_kw_type(keywords))),
      shape: keyword_shape(keywords),
      keywords: keywords
    }

    destination = path(project_dir, :keywords)
    File.mkdir_p!(Path.dirname(destination))
    File.write!(destination, Jason.encode!(payload, pretty: true))
    :ok
  end

  @spec load_keywords(String.t()) :: map() | list() | nil
  def load_keywords(project_dir) do
    keyword_path = path(project_dir, :keywords)

    if File.regular?(keyword_path) do
      case Jason.decode!(File.read!(keyword_path)) do
        %{"keywords" => keywords} when is_map(keywords) or is_list(keywords) -> keywords
        keywords when is_map(keywords) or is_list(keywords) -> keywords
        _other -> nil
      end
    else
      nil
    end
  end

  @spec load_research(String.t(), Research.t()) :: Research.t()
  def load_research(project_dir, %Research{} = research) do
    ensure_project_dirs(project_dir)

    research
    |> maybe_load_text(project_dir, :data_description, :data_description)
    |> maybe_load_text(project_dir, :idea, :idea)
    |> maybe_load_text(project_dir, :methodology, :methodology)
    |> maybe_load_text(project_dir, :results, :results)
    |> maybe_load_text(project_dir, :literature, :literature)
    |> maybe_load_text(project_dir, :referee_report, :referee_report)
    |> maybe_load_keywords(project_dir)
    |> Map.put(:plot_paths, Path.wildcard(Path.join(plots_dir(project_dir), "*.png")))
    |> maybe_set_path(path(project_dir, :paper_tex), :paper_tex_path)
    |> maybe_set_path(path(project_dir, :paper_pdf), :paper_pdf_path)
  end

  defp maybe_load_text(research, project_dir, artifact, field) do
    artifact_path = path(project_dir, artifact)

    if File.regular?(artifact_path) do
      Map.put(research, field, File.read!(artifact_path))
    else
      research
    end
  end

  defp maybe_load_keywords(research, project_dir) do
    case load_keywords(project_dir) do
      keywords when is_map(keywords) or is_list(keywords) ->
        Map.put(research, :keywords, keywords)

      _ ->
        research
    end
  end

  defp maybe_set_path(research, file_path, field) do
    if File.regular?(file_path) do
      Map.put(research, field, file_path)
    else
      research
    end
  end

  defp keyword_shape(keywords) when is_map(keywords), do: "map"
  defp keyword_shape(keywords) when is_list(keywords), do: "list"

  defp infer_kw_type(keywords) when is_map(keywords), do: :aas
  defp infer_kw_type(_keywords), do: :list

  defp normalize_kw_type(kw_type) when is_atom(kw_type), do: Atom.to_string(kw_type)
  defp normalize_kw_type(kw_type) when is_binary(kw_type), do: kw_type
  defp normalize_kw_type(_kw_type), do: "unknown"
end
