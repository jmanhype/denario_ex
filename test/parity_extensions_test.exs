defmodule DenarioEx.ParityExtensionsTest do
  use ExUnit.Case, async: false

  alias DenarioEx
  alias DenarioEx.ArtifactRegistry

  defmodule FakeClient do
    @behaviour DenarioEx.LLMClient

    @impl true
    def complete([%{role: "user", content: prompt}], opts) when is_binary(prompt) do
      send(self(), {:llm_text_prompt, prompt, opts[:model]})

      cond do
        String.contains?(prompt, "[DENARIO_ENHANCE_DESCRIPTION]") ->
          {:ok,
           "\\begin{ENHANCED_DESCRIPTION}Enhanced description with clearer research scope, explicit measurable outcomes, and a short references section.\\end{ENHANCED_DESCRIPTION}"}

        String.contains?(prompt, "[DENARIO_REFEREE_REVIEW]") ->
          {:ok,
           "\\begin{REVIEW}Text-only referee review: the paper is coherent, but the evidence should be expanded and the failure analysis should be more explicit. Score: 5/9.\\end{REVIEW}"}

        true ->
          {:error, {:unexpected_prompt, prompt}}
      end
    end

    def complete([%{role: "user", content: content_parts}], opts) when is_list(content_parts) do
      send(self(), {:llm_multimodal_prompt, content_parts, opts[:model]})

      text_prompt =
        Enum.find_value(content_parts, fn
          %{type: "text", text: text} -> text
          %{"type" => "text", "text" => text} -> text
          _ -> nil
        end)

      if is_binary(text_prompt) and String.contains?(text_prompt, "[DENARIO_REFEREE_REVIEW]") do
        {:ok,
         "\\begin{REVIEW}Image-aware referee review: the paper reads clearly, but one figure is underspecified and the conclusions need tighter support. Score: 6/9.\\end{REVIEW}"}
      else
        {:error, {:unexpected_multimodal_prompt, content_parts}}
      end
    end

    @impl true
    def generate_object([%{role: "user", content: prompt}], _schema, opts) do
      send(self(), {:llm_object_prompt, prompt, opts[:model]})

      cond do
        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][LEVEL1]") ->
          {:ok, %{"selected_keywords" => ["PHYSICS", "TECHNOLOGICAL SCIENCES"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][LEVEL2]") and
            String.contains?(prompt, "PHYSICS") ->
          {:ok, %{"selected_keywords" => ["Acoustics"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][LEVEL2]") and
            String.contains?(prompt, "TECHNOLOGICAL SCIENCES") ->
          {:ok, %{"selected_keywords" => ["Sensor technology"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][LEVEL3]") and
            String.contains?(prompt, "Acoustics") ->
          {:ok, %{"selected_keywords" => ["Noise"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][LEVEL3]") and
            String.contains?(prompt, "Sensor technology") ->
          {:ok, %{"selected_keywords" => ["Remote sensors"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][UNESCO][FINAL]") ->
          {:ok, %{"selected_keywords" => ["PHYSICS", "Acoustics", "Noise"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][AAS]") ->
          {:ok, %{"selected_keywords" => ["A stars", "AB photometry"]}}

        String.contains?(prompt, "[DENARIO_KEYWORDS][AAAI]") ->
          {:ok,
           %{
             "selected_keywords" => [
               "APP: Internet of Things, Sensor Networks & Smart Cities",
               "DMKM: Anomaly/Outlier Detection"
             ]
           }}

        true ->
          {:error, {:unexpected_object_prompt, prompt}}
      end
    end
  end

  defmodule FakeFutureHouseClient do
    @behaviour DenarioEx.FutureHouseClient

    @impl true
    def run_owl_review(prompt, keys, opts) do
      send(self(), {:futurehouse_prompt, prompt, keys.future_house, opts[:base_url]})

      {:ok,
       %{
         "task_id" => "fh-task-123",
         "status" => "success",
         "formatted_answer" =>
           "<DESIRED_RESPONSE_FORMAT>\nAnswer: yes\n\nRelated previous work: Broad literature exists around environmental anomaly monitoring, but the retrieved work does not fully match the proposed framing.\n</DESIRED_RESPONSE_FORMAT>"
       }}
    end
  end

  defmodule NestedAtomFutureHouseClient do
    @behaviour DenarioEx.FutureHouseClient

    @impl true
    def run_owl_review(_prompt, _keys, _opts) do
      {:ok,
       %{
         environment_frame: %{
           state: %{
             state: %{
               response: %{
                 answer: %{
                   formatted_answer:
                     "<DESIRED_RESPONSE_FORMAT>\nAnswer: yes\n\nRelated previous work: Atom-key nested response path works.\n</DESIRED_RESPONSE_FORMAT>"
                 }
               }
             }
           }
         }
       }}
    end
  end

  defmodule FakeRasterizer do
    @behaviour DenarioEx.PdfRasterizer

    @impl true
    def rasterize(pdf_path, output_dir, _opts) do
      send(self(), {:rasterized_pdf, pdf_path, output_dir})
      File.mkdir_p!(output_dir)
      image_path = Path.join(output_dir, "page-001.png")
      File.write!(image_path, "fake png bytes")
      {:ok, [image_path]}
    end
  end

  defmodule MissingRasterizer do
    @behaviour DenarioEx.PdfRasterizer

    @impl true
    def rasterize(_pdf_path, _output_dir, _opts), do: {:error, :renderer_unavailable}
  end

  setup do
    project_dir =
      Path.join(System.tmp_dir!(), "denario_ex_parity_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(project_dir) end)
    {:ok, project_dir: project_dir}
  end

  test "get_keywords persists UNESCO selections and set_all reloads them", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)
    assert {:ok, denario} = DenarioEx.set_idea(denario, "Urban acoustic anomaly detection.")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Use interpretable anomaly scoring.")

    assert {:ok, denario} =
             DenarioEx.set_results(
               denario,
               "Noise spikes separate abnormal events from normal periods."
             )

    assert {:ok, denario} =
             DenarioEx.get_keywords(
               denario,
               nil,
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               kw_type: :unesco,
               n_keywords: 3
             )

    assert denario.research.keywords == ["PHYSICS", "Acoustics", "Noise"]
    assert File.exists?(ArtifactRegistry.path(project_dir, :keywords))

    assert {:ok, denario} = DenarioEx.reset(denario)
    assert {:ok, denario} = DenarioEx.set_all(denario)

    assert denario.research.keywords == ["PHYSICS", "Acoustics", "Noise"]
    assert DenarioEx.show_keywords(denario) == "- PHYSICS\n- Acoustics\n- Noise"
  end

  test "get_keywords supports AAS and AAAI output shapes", %{project_dir: project_dir} do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.get_keywords(
               denario,
               "Astronomical sensor calibration and photometric anomaly analysis.",
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               kw_type: :aas,
               n_keywords: 2
             )

    assert denario.research.keywords == %{
             "A stars" => "http://astrothesaurus.org/uat/5",
             "AB photometry" => "http://astrothesaurus.org/uat/2168"
           }

    assert {:ok, denario} =
             DenarioEx.get_keywords(
               denario,
               "Sensor network anomaly detection for urban deployments.",
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               kw_type: :aaai,
               n_keywords: 2
             )

    assert denario.research.keywords == [
             "APP: Internet of Things, Sensor Networks & Smart Cities",
             "DMKM: Anomaly/Outlier Detection"
           ]
  end

  test "get_keywords emits staged progress callback events", %{project_dir: project_dir} do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_idea(denario, "Urban acoustic anomaly detection.")

    assert {:ok, denario} = DenarioEx.set_method(denario, "Use interpretable anomaly scoring.")

    assert {:ok, denario} =
             DenarioEx.set_results(
               denario,
               "Noise spikes separate abnormal events from normal periods."
             )

    callback = &send(self(), {:keyword_progress, &1})

    assert {:ok, _denario} =
             DenarioEx.get_keywords(
               denario,
               nil,
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               kw_type: :unesco,
               n_keywords: 3,
               progress_callback: callback
             )

    assert_received {:keyword_progress, %{stage: "keywords:start", kind: :started}}
    assert_received {:keyword_progress, %{stage: "keywords:unesco_level1"}}
    assert_received {:keyword_progress, %{stage: "keywords:complete", status: :success}}
  end

  test "enhance_data_description overwrites the persisted description", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Raw notes about a noisy sensor study.")

    assert {:ok, denario} =
             DenarioEx.enhance_data_description(
               denario,
               client: FakeClient,
               summarizer_model: "openai:gpt-4.1-mini",
               summarizer_response_formatter_model: "openai:gpt-4.1-mini"
             )

    assert String.contains?(denario.research.data_description, "Enhanced description")

    assert File.read!(ArtifactRegistry.path(project_dir, :data_description)) ==
             denario.research.data_description
  end

  test "enhance_data_description returns a missing_field error when no description exists", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:error, {:missing_field, :data_description}} =
             DenarioEx.enhance_data_description(
               denario,
               client: FakeClient,
               summarizer_model: "openai:gpt-4.1-mini",
               summarizer_response_formatter_model: "openai:gpt-4.1-mini"
             )
  end

  test "check_idea routes futurehouse mode and writes literature without structured sources", %{
    project_dir: project_dir
  } do
    keys = %DenarioEx.KeyManager{future_house: "fh-key"}

    assert {:ok, denario} =
             DenarioEx.new(project_dir: project_dir, clear_project_dir: true, keys: keys)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} =
             DenarioEx.set_idea(
               denario,
               "Interpretable anomaly detection for urban microclimate sensor networks."
             )

    assert {:ok, denario} =
             DenarioEx.check_idea(
               denario,
               mode: :futurehouse,
               future_house_client: FakeFutureHouseClient,
               base_url: "https://api.platform.futurehouse.org"
             )

    assert String.contains?(
             denario.research.literature,
             "Has anyone worked on or explored the following idea?"
           )

    assert denario.research.literature_sources == []

    assert File.read!(ArtifactRegistry.path(project_dir, :literature)) ==
             denario.research.literature

    assert_received {:futurehouse_prompt, prompt, "fh-key",
                     "https://api.platform.futurehouse.org"}

    assert String.contains?(prompt, "Has anyone worked on or explored the following idea?")
  end

  test "futurehouse workflow emits progress callback events", %{project_dir: project_dir} do
    keys = %DenarioEx.KeyManager{future_house: "fh-key"}

    assert {:ok, denario} =
             DenarioEx.new(project_dir: project_dir, clear_project_dir: true, keys: keys)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} =
             DenarioEx.set_idea(
               denario,
               "Interpretable anomaly detection for urban microclimate sensor networks."
             )

    callback = &send(self(), {:futurehouse_progress, &1})

    assert {:ok, _denario} =
             DenarioEx.check_idea(
               denario,
               mode: :futurehouse,
               future_house_client: FakeFutureHouseClient,
               base_url: "https://api.platform.futurehouse.org",
               progress_callback: callback
             )

    assert_received {:futurehouse_progress, %{stage: "futurehouse:start", kind: :started}}
    assert_received {:futurehouse_progress, %{stage: "futurehouse:complete", status: :success}}
  end

  test "check_idea_futurehouse returns an explicit key error when FUTURE_HOUSE_API_KEY is absent",
       %{
         project_dir: project_dir
       } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpretable anomaly detection.")

    assert {:error, {:missing_api_key, :future_house}} =
             DenarioEx.check_idea_futurehouse(
               denario,
               future_house_client: FakeFutureHouseClient
             )
  end

  test "futurehouse workflow accepts nested atom-key responses without string-to-atom conversion", %{
    project_dir: project_dir
  } do
    keys = %DenarioEx.KeyManager{future_house: "fh-key"}

    assert {:ok, denario} =
             DenarioEx.new(project_dir: project_dir, clear_project_dir: true, keys: keys)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} =
             DenarioEx.set_idea(denario, "Interpretable anomaly detection.")

    assert {:ok, denario} =
             DenarioEx.check_idea(
               denario,
               mode: :futurehouse,
               future_house_client: NestedAtomFutureHouseClient
             )

    assert String.contains?(denario.research.literature, "Atom-key nested response path works.")
  end

  test "referee prefers PDF image review and persists report and output artifacts", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpretable anomaly detection.")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Use blocked temporal splits.")

    assert {:ok, denario} =
             DenarioEx.set_results(denario, "The detector separates abnormal events.")

    pdf_path = ArtifactRegistry.path(project_dir, :paper_pdf)
    File.mkdir_p!(Path.dirname(pdf_path))
    File.write!(pdf_path, "fake pdf bytes")

    assert {:ok, denario} =
             DenarioEx.referee(
               denario,
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               rasterizer: FakeRasterizer
             )

    assert String.contains?(denario.research.referee_report, "Image-aware referee review")

    assert File.read!(ArtifactRegistry.path(project_dir, :referee_report)) ==
             denario.research.referee_report

    assert File.exists?(
             Path.join(ArtifactRegistry.referee_output_dir(project_dir), "page-001.png")
           )

    assert File.exists?(
             Path.join(ArtifactRegistry.referee_output_dir(project_dir), "referee.log")
           )

    assert_received {:rasterized_pdf, ^pdf_path, _output_dir}
    assert_received {:llm_multimodal_prompt, content_parts, "openai:gpt-4.1-mini"}

    assert Enum.any?(content_parts, fn part ->
             Map.get(part, :type) == "image_url" or Map.get(part, "type") == "image_url"
           end)
  end

  test "referee falls back to text review when a PDF image pass is unavailable", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpretable anomaly detection.")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Use blocked temporal splits.")

    assert {:ok, denario} =
             DenarioEx.set_results(denario, "The detector separates abnormal events.")

    tex_path = ArtifactRegistry.path(project_dir, :paper_tex)
    File.mkdir_p!(Path.dirname(tex_path))
    File.write!(tex_path, "\\section{Results}Some paper text")

    assert {:ok, denario} =
             DenarioEx.referee(
               denario,
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               rasterizer: MissingRasterizer
             )

    assert String.contains?(denario.research.referee_report, "Text-only referee review")
    assert_received {:llm_text_prompt, prompt, "openai:gpt-4.1-mini"}
    assert String.contains?(prompt, "[DENARIO_REFEREE_REVIEW]")
  end

  test "referee ignores stale in-memory paper paths when the canonical artifact exists", %{
    project_dir: project_dir
  } do
    assert {:ok, denario} = DenarioEx.new(project_dir: project_dir, clear_project_dir: true)

    assert {:ok, denario} =
             DenarioEx.set_data_description(denario, "Urban sensor anomaly project.")

    assert {:ok, denario} = DenarioEx.set_idea(denario, "Interpretable anomaly detection.")
    assert {:ok, denario} = DenarioEx.set_method(denario, "Use blocked temporal splits.")

    assert {:ok, denario} =
             DenarioEx.set_results(denario, "The detector separates abnormal events.")

    pdf_path = ArtifactRegistry.path(project_dir, :paper_pdf)
    File.mkdir_p!(Path.dirname(pdf_path))
    File.write!(pdf_path, "fake pdf bytes")

    denario = %{
      denario
      | research: %{
          denario.research
          | paper_pdf_path: Path.join(project_dir, "paper/missing.pdf")
        }
    }

    assert {:ok, _denario} =
             DenarioEx.referee(
               denario,
               client: FakeClient,
               llm: "openai:gpt-4.1-mini",
               rasterizer: FakeRasterizer
             )

    assert_received {:rasterized_pdf, ^pdf_path, _output_dir}
  end
end
