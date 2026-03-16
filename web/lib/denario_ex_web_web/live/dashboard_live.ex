defmodule DenarioExUIWeb.DashboardLive do
  use DenarioExUIWeb, :live_view

  alias DenarioExUI.{PhaseRunner, Projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Control Room")
     |> assign(:project_dir_input, "")
     |> assign(:project, nil)
     |> assign(:artifact_values, blank_artifact_values())
     |> assign(:phase_specs, Projects.phase_specs(nil))
     |> assign(:settings, Projects.default_settings())
     |> assign(:activity, [])
     |> assign(:running_phases, MapSet.new())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_dir = Map.get(params, "project_dir", "")
    socket = assign(socket, :project_dir_input, project_dir)

    case String.trim(project_dir) do
      "" ->
        {:noreply, clear_project(socket)}

      _ ->
        case Projects.load(project_dir) do
          {:ok, snapshot} ->
            {:noreply, assign_project(socket, snapshot)}

          {:error, reason} ->
            {:noreply,
             socket
             |> clear_project()
             |> put_flash(:error, error_message(reason))}
        end
    end
  end

  @impl true
  def handle_event("open_project", %{"project" => %{"project_dir" => project_dir}}, socket) do
    trimmed = String.trim(project_dir)

    if trimmed == "" do
      {:noreply, put_flash(socket, :error, "Enter a project directory first.")}
    else
      {:noreply, push_patch(socket, to: ~p"/?project_dir=#{trimmed}")}
    end
  end

  def handle_event("edit_artifact", %{"artifact" => %{"name" => name, "value" => value}}, socket) do
    {:noreply,
     assign(socket, :artifact_values, Map.put(socket.assigns.artifact_values, name, value))}
  end

  def handle_event("save_artifact", %{"artifact" => %{"name" => name, "value" => value}}, socket) do
    case socket.assigns.project do
      nil ->
        {:noreply, put_flash(socket, :error, "Open a project before saving artifacts.")}

      project ->
        case Projects.save_artifact(project.project_dir, name, value) do
          {:ok, snapshot} ->
            {:noreply,
             socket
             |> assign_project(snapshot)
             |> note_activity(:saved, "#{artifact_label(name)} saved.")
             |> put_flash(:info, "#{artifact_label(name)} saved.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, error_message(reason))}
        end
    end
  end

  def handle_event("update_settings", %{"settings" => settings}, socket) do
    {:noreply, assign(socket, :settings, normalize_settings(settings))}
  end

  def handle_event("run_phase", %{"phase" => phase}, socket) do
    cond do
      is_nil(socket.assigns.project) ->
        {:noreply, put_flash(socket, :error, "Open a project before launching a phase.")}

      MapSet.member?(socket.assigns.running_phases, phase) ->
        {:noreply, socket}

      true ->
        case PhaseRunner.start(
               self(),
               socket.assigns.project.project_dir,
               phase,
               socket.assigns.settings
             ) do
          {:ok, _pid} ->
            {:noreply,
             socket
             |> update(:running_phases, &MapSet.put(&1, phase))
             |> note_activity(:running, "#{Projects.phase_label(phase)} started.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, error_message(reason))}
        end
    end
  end

  @impl true
  def handle_info({:phase_started, _phase}, socket) do
    {:noreply, socket}
  end

  def handle_info({:phase_finished, phase, {:ok, snapshot, message}}, socket) do
    {:noreply,
     socket
     |> update(:running_phases, &MapSet.delete(&1, phase))
     |> assign_project(snapshot)
     |> note_activity(:success, message)
     |> put_flash(:info, message)}
  end

  def handle_info({:phase_finished, phase, {:error, reason}}, socket) do
    label = Projects.phase_label(phase)

    {:noreply,
     socket
     |> update(:running_phases, &MapSet.delete(&1, phase))
     |> note_activity(:error, "#{label} failed: #{error_message(reason)}")
     |> put_flash(:error, "#{label} failed: #{error_message(reason)}")}
  end

  attr :snapshot, :map, required: true
  attr :section, :map, required: true
  attr :artifact_values, :map, required: true

  defp artifact_editor(assigns) do
    ~H"""
    <section class="panel-shell">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="eyebrow">{@section.label}</p>
          <p class="panel-copy mt-2">{@section.helper}</p>
        </div>
        <span class={artifact_badge_class(Map.get(@snapshot.artifact_presence, @section.key, false))}>
          {if Map.get(@snapshot.artifact_presence, @section.key, false), do: "Ready", else: "Missing"}
        </span>
      </div>

      <.form
        for={%{}}
        as={:artifact}
        phx-change="edit_artifact"
        phx-submit="save_artifact"
        class="mt-5 space-y-3"
      >
        <input type="hidden" name="artifact[name]" value={@section.key} />
        <textarea
          name="artifact[value]"
          rows="9"
          phx-debounce="300"
          class="artifact-input"
        ><%= Map.get(@artifact_values, @section.key, "") %></textarea>
        <div class="flex items-center justify-between gap-4">
          <span class="tiny-copy">
            {String.length(Map.get(@artifact_values, @section.key, ""))} characters
          </span>
          <button type="submit" class="action-button action-button--secondary">
            Save
          </button>
        </div>
      </.form>
    </section>
    """
  end

  attr :spec, :map, required: true
  attr :running_phases, :any, required: true

  defp phase_button(assigns) do
    running? = MapSet.member?(assigns.running_phases, assigns.spec.key)
    disabled? = !assigns.spec.ready or running?
    assigns = assign(assigns, :running?, running?)
    assigns = assign(assigns, :disabled?, disabled?)

    ~H"""
    <button
      type="button"
      phx-click="run_phase"
      phx-value-phase={@spec.key}
      disabled={@disabled?}
      class={phase_button_class(@disabled?, @running?)}
    >
      <span class="text-left">
        <span class="block font-semibold">{@spec.label}</span>
        <span class="mt-1 block text-xs opacity-80">{@spec.description}</span>
      </span>
      <span class="text-xs uppercase tracking-[0.22em] opacity-80">
        {cond do
          @running? -> "Running"
          @spec.ready -> "Ready"
          true -> "Blocked"
        end}
      </span>
    </button>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="control-shell">
      <.flash_group flash={@flash} />

      <section class="hero-shell">
        <div class="max-w-3xl">
          <p class="eyebrow">Denario Ex UI</p>
          <h1 class="hero-title">Denario Ex Control Room</h1>
          <p class="hero-copy">
            A Phoenix LiveView shell over the Elixir research core. Open a project directory,
            edit the artifact chain, and launch the workflow phases without leaving the browser.
          </p>
        </div>
        <div class="hero-orbit" aria-hidden="true">
          <span class="hero-orbit__ring"></span>
          <span class="hero-orbit__dot"></span>
        </div>
      </section>

      <div class="dashboard-grid">
        <aside class="space-y-6">
          <section class="panel-shell">
            <p class="eyebrow">Open Or Create Project</p>
            <.form for={%{}} as={:project} phx-submit="open_project" class="mt-4 space-y-3">
              <input
                type="text"
                name="project[project_dir]"
                value={@project_dir_input}
                class="artifact-input artifact-input--single"
                placeholder="/tmp/denario_ex_project"
              />
              <button type="submit" class="action-button action-button--primary w-full">
                Open Directory
              </button>
            </.form>
          </section>

          <section class="panel-shell">
            <p class="eyebrow">Model Settings</p>
            <.form for={%{}} as={:settings} phx-change="update_settings" class="mt-4 space-y-4">
              <label class="field-shell">
                <span class="field-label">LLM</span>
                <input
                  type="text"
                  name="settings[llm]"
                  value={@settings["llm"]}
                  class="artifact-input artifact-input--single"
                />
              </label>

              <label class="field-shell">
                <span class="field-label">Literature Mode</span>
                <select name="settings[literature_mode]" class="artifact-input artifact-input--single">
                  <option
                    value="semantic_scholar"
                    selected={@settings["literature_mode"] == "semantic_scholar"}
                  >
                    Semantic Scholar / OpenAlex
                  </option>
                  <option value="futurehouse" selected={@settings["literature_mode"] == "futurehouse"}>
                    FutureHouse / Edison
                  </option>
                </select>
              </label>

              <label class="field-shell">
                <span class="field-label">Keyword Taxonomy</span>
                <select
                  name="settings[keyword_taxonomy]"
                  class="artifact-input artifact-input--single"
                >
                  <option value="unesco" selected={@settings["keyword_taxonomy"] == "unesco"}>
                    UNESCO
                  </option>
                  <option value="aas" selected={@settings["keyword_taxonomy"] == "aas"}>AAS</option>
                  <option value="aaai" selected={@settings["keyword_taxonomy"] == "aaai"}>
                    AAAI
                  </option>
                </select>
              </label>

              <label class="field-shell">
                <span class="field-label">Paper Journal</span>
                <select name="settings[journal]" class="artifact-input artifact-input--single">
                  <option value="none" selected={@settings["journal"] == "none"}>Generic</option>
                  <option value="neurips" selected={@settings["journal"] == "neurips"}>
                    NeurIPS
                  </option>
                  <option value="icml" selected={@settings["journal"] == "icml"}>ICML</option>
                  <option value="aps" selected={@settings["journal"] == "aps"}>APS</option>
                  <option value="aas" selected={@settings["journal"] == "aas"}>AAS</option>
                  <option value="jhep" selected={@settings["journal"] == "jhep"}>JHEP</option>
                  <option value="pasj" selected={@settings["journal"] == "pasj"}>PASJ</option>
                </select>
              </label>

              <label class="field-shell field-shell--row">
                <input type="hidden" name="settings[compile_paper]" value="false" />
                <input
                  type="checkbox"
                  name="settings[compile_paper]"
                  value="true"
                  checked={@settings["compile_paper"] in ["true", true]}
                  class="h-4 w-4 rounded border-white/20 bg-black/20 text-amber-400 focus:ring-amber-400"
                />
                <span class="field-label !mb-0">Compile paper PDF after generation</span>
              </label>
            </.form>
          </section>

          <section class="panel-shell">
            <p class="eyebrow">Project State</p>

            <%= if @project do %>
              <dl class="mt-4 space-y-3 text-sm">
                <div class="state-row">
                  <dt>Project</dt>
                  <dd class="state-value">{@project.project_dir}</dd>
                </div>
                <div class="state-row">
                  <dt>Keywords</dt>
                  <dd class="state-value">{@project.keywords_count}</dd>
                </div>
                <div class="state-row">
                  <dt>Literature Sources</dt>
                  <dd class="state-value">{@project.literature_source_count}</dd>
                </div>
                <div class="state-row">
                  <dt>Plots</dt>
                  <dd class="state-value">{length(@project.plot_paths)}</dd>
                </div>
                <div class="state-row">
                  <dt>PDF</dt>
                  <dd class="state-value">
                    {if @project.available_outputs["paper_pdf"], do: "Ready", else: "Missing"}
                  </dd>
                </div>
              </dl>
            <% else %>
              <p class="panel-copy mt-4">
                Open a project directory to load the Denario artifact graph from disk.
              </p>
            <% end %>
          </section>

          <section class="panel-shell">
            <p class="eyebrow">Phase Controls</p>
            <div class="mt-4 grid gap-3">
              <.phase_button :for={spec <- @phase_specs} spec={spec} running_phases={@running_phases} />
            </div>
          </section>

          <section class="panel-shell">
            <p class="eyebrow">Activity</p>

            <%= if @activity == [] do %>
              <p class="panel-copy mt-4">No activity yet. Launch a phase or save an artifact.</p>
            <% else %>
              <div class="mt-4 space-y-3">
                <div :for={entry <- @activity} class="activity-row">
                  <span class={activity_tone_class(entry.tone)}>{entry.tone}</span>
                  <div class="min-w-0">
                    <p class="text-sm text-white">{entry.message}</p>
                    <p class="tiny-copy mt-1">{entry.at}</p>
                  </div>
                </div>
              </div>
            <% end %>
          </section>
        </aside>

        <section class="space-y-6">
          <%= for section <- Projects.editable_sections() do %>
            <.artifact_editor
              snapshot={@project || %{artifact_presence: %{}}}
              section={section}
              artifact_values={@artifact_values}
            />
          <% end %>

          <section class="panel-shell">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="eyebrow">Outputs</p>
                <p class="panel-copy mt-2">
                  Inline plots plus direct links to the current TeX, PDF, and referee log.
                </p>
              </div>
            </div>

            <%= if @project do %>
              <div class="mt-5 flex flex-wrap gap-3">
                <a
                  :if={@project.paper_tex_path}
                  href={~p"/artifacts?project_dir=#{@project.project_dir}&kind=paper_tex"}
                  class="output-link"
                  target="_blank"
                >
                  Open TeX
                </a>
                <a
                  :if={@project.paper_pdf_path}
                  href={~p"/artifacts?project_dir=#{@project.project_dir}&kind=paper_pdf"}
                  class="output-link"
                  target="_blank"
                >
                  Open PDF
                </a>
                <a
                  :if={@project.referee_log_path}
                  href={~p"/artifacts?project_dir=#{@project.project_dir}&kind=referee_log"}
                  class="output-link"
                  target="_blank"
                >
                  Open Referee Log
                </a>
              </div>

              <%= if @project.keywords_preview != "" do %>
                <div class="output-shell mt-5">
                  <p class="field-label">Keywords</p>
                  <pre class="keywords-preview">{@project.keywords_preview}</pre>
                </div>
              <% end %>

              <%= if @project.plot_paths != [] do %>
                <div class="plot-grid mt-5">
                  <a
                    :for={plot_path <- @project.plot_paths}
                    href={
                      ~p"/artifacts?project_dir=#{@project.project_dir}&kind=plot&name=#{Path.basename(plot_path)}"
                    }
                    class="plot-card"
                    target="_blank"
                  >
                    <img
                      src={
                        ~p"/artifacts?project_dir=#{@project.project_dir}&kind=plot&name=#{Path.basename(plot_path)}"
                      }
                      alt={Path.basename(plot_path)}
                    />
                    <span>{Path.basename(plot_path)}</span>
                  </a>
                </div>
              <% else %>
                <p class="panel-copy mt-5">No plots have been generated yet.</p>
              <% end %>
            <% else %>
              <p class="panel-copy mt-5">Open a project to browse its output artifacts.</p>
            <% end %>
          </section>
        </section>
      </div>
    </div>
    """
  end

  defp blank_artifact_values do
    Map.new(Projects.editable_sections(), fn section -> {section.key, ""} end)
  end

  defp clear_project(socket) do
    socket
    |> assign(:project, nil)
    |> assign(:artifact_values, blank_artifact_values())
    |> assign(:phase_specs, Projects.phase_specs(nil))
  end

  defp assign_project(socket, snapshot) do
    socket
    |> assign(:project, snapshot)
    |> assign(:artifact_values, snapshot.artifact_values)
    |> assign(:phase_specs, Projects.phase_specs(snapshot))
  end

  defp note_activity(socket, tone, message) do
    entry = %{
      tone: tone,
      message: message,
      at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> to_string()
    }

    update(socket, :activity, fn entries -> [entry | Enum.take(entries, 19)] end)
  end

  defp normalize_settings(settings) do
    Projects.default_settings()
    |> Map.merge(settings)
    |> Map.update!("compile_paper", fn value ->
      if value in [true, "true", "on", "1"], do: "true", else: "false"
    end)
  end

  defp artifact_label(name) do
    case Enum.find(Projects.editable_sections(), &(&1.key == name)) do
      nil -> name
      section -> section.label
    end
  end

  defp error_message(:missing_project_dir), do: "Missing project directory."
  defp error_message({:missing_field, field}), do: "Missing required field: #{field}"
  defp error_message({:unknown_artifact, artifact}), do: "Unknown artifact: #{artifact}"
  defp error_message({:unsupported_phase, phase}), do: "Unsupported phase: #{phase}"

  defp error_message({:unsupported_literature_mode, mode}),
    do: "Unsupported literature mode: #{mode}"

  defp error_message({:missing_api_key, provider}), do: "Missing API key for #{provider}."
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)

  defp artifact_badge_class(true), do: "state-pill state-pill--ready"
  defp artifact_badge_class(false), do: "state-pill state-pill--missing"

  defp phase_button_class(true, false),
    do: "phase-button phase-button--disabled"

  defp phase_button_class(_disabled, true),
    do: "phase-button phase-button--running"

  defp phase_button_class(false, false),
    do: "phase-button"

  defp activity_tone_class(:success), do: "activity-pill activity-pill--success"
  defp activity_tone_class(:error), do: "activity-pill activity-pill--error"
  defp activity_tone_class(:saved), do: "activity-pill activity-pill--saved"
  defp activity_tone_class(_tone), do: "activity-pill activity-pill--running"
end
