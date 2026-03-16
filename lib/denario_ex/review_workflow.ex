defmodule DenarioEx.ReviewWorkflow do
  @moduledoc false

  alias DenarioEx.{
    AI,
    ArtifactRegistry,
    LLM,
    ReqLLMClient,
    SystemPdfRasterizer,
    Text,
    WorkflowPrompts
  }

  @spec run(DenarioEx.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(session, opts \\ []) do
    client = Keyword.get(opts, :client, ReqLLMClient)
    rasterizer = Keyword.get(opts, :rasterizer, SystemPdfRasterizer)
    referee_output_dir = ArtifactRegistry.referee_output_dir(session.project_dir)
    log_path = Path.join(referee_output_dir, "referee.log")

    with {:ok, llm} <- LLM.parse(Keyword.get(opts, :llm, "gemini-2.5-flash")),
         :ok <- File.mkdir_p(referee_output_dir),
         {:ok, request} <- build_request(session, referee_output_dir, rasterizer, opts),
         {:ok, review_text} <- run_review(client, request, llm, session.keys),
         {:ok, report} <- Text.extract_block_or_fallback(review_text, "REVIEW") do
      File.write!(log_path, render_log(request, report))

      {:ok,
       %{
         report: report,
         log_path: log_path,
         image_paths: Map.get(request, :image_paths, []),
         mode: request.mode
       }}
    end
  end

  defp build_request(session, referee_output_dir, rasterizer, opts) do
    pdf_path =
      Keyword.get(opts, :paper_pdf, ArtifactRegistry.path(session.project_dir, :paper_pdf))

    tex_path =
      Keyword.get(opts, :paper_tex, ArtifactRegistry.path(session.project_dir, :paper_tex))

    paper_source = source_text(session, tex_path)

    cond do
      File.regular?(pdf_path) ->
        case rasterizer.rasterize(pdf_path, referee_output_dir, opts) do
          {:ok, image_paths} when image_paths != [] ->
            {:ok,
             %{
               mode: :pdf,
               image_paths: image_paths,
               messages: multimodal_messages(session, paper_source, image_paths),
               source_path: pdf_path
             }}

          _ ->
            {:ok,
             %{
               mode: :text,
               image_paths: [],
               messages: text_messages(session, paper_source),
               source_path: tex_path
             }}
        end

      true ->
        {:ok,
         %{
           mode: :text,
           image_paths: [],
           messages: text_messages(session, paper_source),
           source_path: tex_path
         }}
    end
  end

  defp run_review(client, %{mode: :pdf, messages: messages}, llm, keys),
    do: AI.complete_messages(client, messages, llm, keys)

  defp run_review(client, %{mode: :text, messages: messages}, llm, keys),
    do: AI.complete_messages(client, messages, llm, keys)

  defp multimodal_messages(session, paper_source, image_paths) do
    text_prompt = WorkflowPrompts.referee_review_prompt(session.research, paper_source)

    image_parts =
      Enum.map(image_paths, fn image_path ->
        %{
          type: "image_url",
          image_url: %{
            url: "data:image/png;base64," <> Base.encode64(File.read!(image_path))
          }
        }
      end)

    [
      %{
        role: "user",
        content: [%{type: "text", text: text_prompt} | image_parts]
      }
    ]
  end

  defp text_messages(session, paper_source) do
    [
      %{
        role: "user",
        content: WorkflowPrompts.referee_review_prompt(session.research, paper_source)
      }
    ]
  end

  defp source_text(session, tex_path) do
    cond do
      File.regular?(tex_path) ->
        File.read!(tex_path)

      true ->
        """
        Idea:
        #{session.research.idea}

        Methods:
        #{session.research.methodology}

        Results:
        #{session.research.results}

        Literature:
        #{session.research.literature}
        """
    end
  end

  defp render_log(request, report) do
    """
    mode=#{request.mode}
    source_path=#{request.source_path}
    image_count=#{length(Map.get(request, :image_paths, []))}

    #{report}
    """
  end
end
