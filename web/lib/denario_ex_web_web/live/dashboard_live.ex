defmodule DenarioExUIWeb.DashboardLive do
  use DenarioExUIWeb, :live_view

  alias DenarioExUI.{PhaseEvents, PhaseRunner, Projects}

  @workflow_groups [
    %{
      title: "Shape The Paper",
      description: "Turn the raw brief into a coherent idea and method.",
      phases: ["enhance_data_description", "get_idea", "get_method"]
    },
    %{
      title: "Prove The Work",
      description: "Generate evidence, novelty checks, and taxonomy-backed metadata.",
      phases: ["get_results", "check_idea", "get_keywords"]
    },
    %{
      title: "Publish And Critique",
      description: "Draft the paper package and pressure-test it with a referee pass.",
      phases: ["get_paper", "referee"]
    }
  ]

  @artifact_keys Enum.map(Projects.editable_sections(), & &1.key)
  @default_artifact_key hd(@artifact_keys)

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
     |> assign(:running_phases, MapSet.new())
     |> assign(:run_states, %{})
     |> assign(:run_order, [])
     |> assign(:selected_run_id, nil)
     |> assign(:active_artifact_key, @default_artifact_key)
     |> assign(:subscribed_project_dir, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_dir = Map.get(params, "project_dir", "")

    socket =
      socket
      |> assign(:project_dir_input, project_dir)
      |> maybe_subscribe(project_dir)

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

  def handle_event("select_run", %{"run_id" => run_id}, socket) do
    {:noreply, assign(socket, :selected_run_id, run_id)}
  end

  def handle_event("select_artifact", %{"artifact" => artifact_key}, socket) do
    if artifact_key in @artifact_keys do
      {:noreply, assign(socket, :active_artifact_key, artifact_key)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_run", %{"run_id" => run_id}, socket) do
    case PhaseRunner.cancel(run_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Run cancelled.")}

      {:error, :unknown_run} ->
        {:noreply, put_flash(socket, :error, "Run is no longer active.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("retry_run", %{"run_id" => run_id}, socket) do
    cond do
      is_nil(socket.assigns.project) ->
        {:noreply, put_flash(socket, :error, "Open a project before retrying a phase.")}

      run = selected_run(socket.assigns.run_states, run_id) ->
        case PhaseRunner.start(
               self(),
               socket.assigns.project.project_dir,
               run.phase,
               socket.assigns.settings
             ) do
          {:ok, new_run_id} ->
            {:noreply, assign(socket, :selected_run_id, new_run_id)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, error_message(reason))}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Could not find that run to retry.")}
    end
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

  def handle_info({:phase_event, event}, socket) do
    {:noreply, apply_phase_event(socket, event)}
  end

  def handle_info({:phase_finished, phase, {:ok, snapshot, message}}, socket) do
    event = %{
      run_id: PhaseEvents.new_run_id(),
      phase: phase,
      status: :success,
      kind: :finished,
      progress: 100,
      message: message,
      snapshot: snapshot
    }

    {:noreply, apply_phase_event(socket, event) |> put_flash(:info, message)}
  end

  def handle_info({:phase_finished, phase, {:error, reason}}, socket) do
    label = Projects.phase_label(phase)
    message = "#{label} failed: #{error_message(reason)}"

    event = %{
      run_id: PhaseEvents.new_run_id(),
      phase: phase,
      status: :error,
      kind: :finished,
      progress: 100,
      message: message
    }

    {:noreply, apply_phase_event(socket, event) |> put_flash(:error, message)}
  end

  attr :snapshot, :map, required: true
  attr :section, :map, required: true
  attr :artifact_values, :map, required: true

  defp artifact_editor(assigns) do
    ~H"""
    <section class="workspace-editor">
      <div class="workspace-editor__header">
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
        class="mt-6 space-y-4"
      >
        <input type="hidden" name="artifact[name]" value={@section.key} />
        <textarea
          name="artifact[value]"
          rows="14"
          phx-debounce="300"
          class="artifact-input"
        ><%= Map.get(@artifact_values, @section.key, "") %></textarea>
        <div class="workspace-editor__footer">
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
      <span class="phase-button__copy">
        <span class="phase-button__title">{@spec.label}</span>
        <span class="phase-button__body">{@spec.description}</span>
      </span>
      <span class="phase-button__state">
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
    <% current_run = current_run(@run_states, @selected_run_id, @run_order) %>
    <% next_action = next_action(@project, @phase_specs, @running_phases) %>
    <% active_section = active_section(@active_artifact_key) %>
    <% completion = project_completion(@project) %>
    <div class="control-shell">
      <.flash_group flash={@flash} />

      <section class="hero-shell">
        <div class="hero-grid">
          <div class="hero-copy-stack">
            <div class="hero-intro">
              <p class="eyebrow">Denario Ex UI</p>
              <h1 class="hero-title">A research cockpit that tells you what to do next.</h1>
              <p class="hero-copy">
                The backend is already strong. This screen is here to keep the project legible:
                shape the brief, run the next phase, inspect the evidence, and ship a paper
                without getting buried in pipeline internals.
              </p>
            </div>

            <div class="hero-pill-row">
              <span class="hero-pill">Artifact-native workflow</span>
              <span class="hero-pill">Live run telemetry</span>
              <span class="hero-pill">Paper-ready outputs</span>
            </div>

            <%= if @project do %>
              <div class="hero-project-banner">
                <div class="min-w-0">
                  <p class="field-label">Loaded Project</p>
                  <p class="hero-project-path">{@project.project_dir}</p>
                </div>
                <span class="hero-project-slug">{project_slug(@project.project_dir)}</span>
              </div>

              <div class="hero-action-strip">
                <div class="hero-next-step">
                  <p class="field-label">Recommended Next Step</p>
                  <p class="hero-next-step__title">{next_action.label}</p>
                  <p class="hero-next-step__copy">{next_action.description}</p>
                </div>

                <div class="hero-action-buttons">
                  <button
                    :if={next_action.kind == :phase}
                    type="button"
                    phx-click="run_phase"
                    phx-value-phase={next_action.key}
                    disabled={next_action.disabled}
                    class="action-button action-button--primary"
                  >
                    {next_action.cta}
                  </button>

                  <button
                    type="button"
                    phx-click="run_phase"
                    phx-value-phase="research_pilot"
                    disabled={MapSet.member?(@running_phases, "research_pilot") or !phase_ready?(@phase_specs, "research_pilot")}
                    class="action-button action-button--ghost"
                  >
                    Run Full Workflow
                  </button>
                </div>
              </div>
            <% else %>
              <div class="hero-empty-grid">
                <div class="hero-empty-card">
                  <p class="field-label">1. Open A Directory</p>
                  <p>Point the UI at a DenarioEx project folder to load its full artifact graph.</p>
                </div>
                <div class="hero-empty-card">
                  <p class="field-label">2. Run The Next Phase</p>
                  <p>Use the workflow rail to move one step at a time or fire the full workflow.</p>
                </div>
                <div class="hero-empty-card">
                  <p class="field-label">3. Refine The Paper</p>
                  <p>Edit the active artifact, inspect outputs, then iterate until the paper is clean.</p>
                </div>
              </div>
            <% end %>
          </div>

          <div class="hero-status-panel">
            <%= if @project do %>
              <div class="hero-status-panel__top">
                <div class="progress-orb" style={progress_orb_style(completion)}>
                  <div class="progress-orb__inner">
                    <span class="progress-orb__value">{completion}%</span>
                    <span class="progress-orb__label">Project Complete</span>
                  </div>
                </div>

                <div class="hero-status-copy">
                  <p class="field-label">Project Pulse</p>
                  <h2>{pulse_headline(@project, current_run)}</h2>
                  <p>{pulse_copy(@project, current_run)}</p>
                </div>
              </div>

              <div class="hero-metric-grid">
                <div class="hero-metric-card">
                  <span class="hero-metric-card__value">{artifact_completion_count(@project)}/6</span>
                  <span class="hero-metric-card__label">Core Artifacts</span>
                </div>
                <div class="hero-metric-card">
                  <span class="hero-metric-card__value">{output_ready_count(@project)}</span>
                  <span class="hero-metric-card__label">Outputs Ready</span>
                </div>
                <div class="hero-metric-card">
                  <span class="hero-metric-card__value">{@project.literature_source_count}</span>
                  <span class="hero-metric-card__label">Sources Loaded</span>
                </div>
                <div class="hero-metric-card">
                  <span class="hero-metric-card__value">{length(@project.plot_paths)}</span>
                  <span class="hero-metric-card__label">Plots Generated</span>
                </div>
              </div>

              <%= if current_run do %>
                <div class="run-spotlight">
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <p class="field-label">{run_spotlight_label(current_run)}</p>
                      <p class="run-spotlight__title">{current_run.phase_label}</p>
                      <p class="run-spotlight__copy">{current_run.message}</p>
                    </div>
                    <span class={run_status_class(current_run.status)}>{current_run.status}</span>
                  </div>

                  <div class="mt-4">
                    <div class="run-progress">
                      <span
                        class="run-progress__fill"
                        style={"width: #{current_run.progress}%"}
                      ></span>
                    </div>
                    <div class="mt-2 flex items-center justify-between gap-4">
                      <span class="tiny-copy">{current_run.progress}%</span>
                      <span class="tiny-copy">{current_run.at}</span>
                    </div>
                  </div>
                </div>
              <% else %>
                <div class="run-spotlight run-spotlight--idle">
                  <p class="field-label">Current Run</p>
                  <p class="run-spotlight__title">No active execution</p>
                  <p class="run-spotlight__copy">
                    Launch the recommended next phase and the monitor will take over from there.
                  </p>
                </div>
              <% end %>
            <% else %>
              <div class="hero-status-empty">
                <p class="field-label">What This UI Is Good At</p>
                <ul class="hero-list">
                  <li>Keeping the artifact chain visible instead of burying it in logs.</li>
                  <li>Showing the next rational move without forcing full-or-nothing runs.</li>
                  <li>Streaming phase progress, run history, and paper outputs in one place.</li>
                </ul>
              </div>
            <% end %>
          </div>
        </div>
      </section>

      <div class="dashboard-grid">
        <aside class="dashboard-sidebar">
          <section class="panel-shell panel-shell--project">
            <p class="eyebrow">Open Or Create Project</p>
            <p class="panel-copy mt-3">
              Point the control room at a project directory. The UI reloads the saved artifacts and
              outputs directly from disk.
            </p>

            <.form for={%{}} as={:project} phx-submit="open_project" class="mt-5 space-y-3">
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

            <%= if @project do %>
              <div class="project-chip-grid">
                <div class="project-chip">
                  <span class="project-chip__label">Keywords</span>
                  <span class="project-chip__value">{@project.keywords_count}</span>
                </div>
                <div class="project-chip">
                  <span class="project-chip__label">Sources</span>
                  <span class="project-chip__value">{@project.literature_source_count}</span>
                </div>
                <div class="project-chip">
                  <span class="project-chip__label">Plots</span>
                  <span class="project-chip__value">{length(@project.plot_paths)}</span>
                </div>
                <div class="project-chip">
                  <span class="project-chip__label">PDF</span>
                  <span class="project-chip__value">
                    {if @project.available_outputs["paper_pdf"], do: "Ready", else: "Missing"}
                  </span>
                </div>
              </div>
            <% end %>
          </section>

          <section class="panel-shell">
            <div class="workflow-panel__header">
              <div>
                <p class="eyebrow">Workflow Rail</p>
                <p class="panel-copy mt-2">
                  Move one phase at a time or orchestrate the whole chain when the brief is ready.
                </p>
              </div>
              <button
                type="button"
                phx-click="run_phase"
                phx-value-phase="research_pilot"
                disabled={MapSet.member?(@running_phases, "research_pilot") or !phase_ready?(@phase_specs, "research_pilot")}
                class="action-button action-button--ghost"
              >
                Full Workflow
              </button>
            </div>

            <div class="workflow-group-list">
              <div :for={group <- workflow_groups(@phase_specs)} class="workflow-group">
                <div class="workflow-group__copy">
                  <p class="workflow-group__title">{group.title}</p>
                  <p class="workflow-group__description">{group.description}</p>
                </div>
                <div class="grid gap-3">
                  <.phase_button
                    :for={spec <- group.specs}
                    spec={spec}
                    running_phases={@running_phases}
                  />
                </div>
              </div>
            </div>
          </section>

          <section class="panel-shell">
            <p class="eyebrow">Run Monitor</p>

            <%= if current_run do %>
              <div class="run-monitor-shell">
                <div class="run-monitor-shell__header">
                  <div>
                    <p class="field-label">Selected Run</p>
                    <p class="run-monitor-shell__title">{current_run.phase_label}</p>
                    <p class="panel-copy mt-2">{current_run.message}</p>
                  </div>
                  <div class="flex flex-wrap justify-end gap-2">
                    <button
                      :if={current_run.status == :running}
                      type="button"
                      phx-click="cancel_run"
                      phx-value-run_id={current_run.run_id}
                      class="action-button action-button--secondary"
                    >
                      Cancel Run
                    </button>
                    <button
                      :if={current_run.status in [:success, :error, :cancelled]}
                      type="button"
                      phx-click="retry_run"
                      phx-value-run_id={current_run.run_id}
                      class="action-button action-button--primary"
                    >
                      Retry Run
                    </button>
                  </div>
                </div>

                <div class="run-progress mt-4">
                  <span
                    class="run-progress__fill"
                    style={"width: #{current_run.progress}%"}
                  ></span>
                </div>

                <div class="mt-3 flex items-center justify-between gap-4">
                  <span class="tiny-copy">{current_run.progress}%</span>
                  <span class="tiny-copy">{current_run.at}</span>
                </div>

                <div class="log-shell">
                  <div :for={entry <- current_run.logs} class="log-row">
                    <span class={activity_tone_class(entry.status)}>{entry.kind}</span>
                    <div class="min-w-0">
                      <p class="text-sm text-white">{entry.message}</p>
                      <p class="tiny-copy mt-1">{entry.at}</p>
                    </div>
                  </div>
                </div>

                <%= if length(@run_order) > 1 do %>
                  <div class="run-history">
                    <p class="field-label">Recent Runs</p>
                    <div class="run-history__list">
                      <button
                        :for={run <- ordered_runs(@run_states, @run_order)}
                        :if={run.run_id != current_run.run_id}
                        type="button"
                        phx-click="select_run"
                        phx-value-run_id={run.run_id}
                        class={run_card_class(@selected_run_id == run.run_id)}
                      >
                        <div class="flex items-start justify-between gap-4">
                          <div class="min-w-0">
                            <p class="text-sm font-semibold text-white">{run.phase_label}</p>
                            <p class="tiny-copy mt-1">{run.message}</p>
                          </div>
                          <span class={run_status_class(run.status)}>{run.status}</span>
                        </div>
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="panel-copy mt-4">
                No runs yet. Launch a phase to start streaming progress and log entries.
              </p>
            <% end %>
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

        <section class="dashboard-main">
          <section class="panel-shell workspace-shell">
            <div class="workspace-shell__header">
              <div>
                <p class="eyebrow">Artifact Studio</p>
                <h2 class="workspace-shell__title">
                  <%= if active_section do %>
                    {active_section.label}
                  <% else %>
                    Project Artifacts
                  <% end %>
                </h2>
                <p class="panel-copy mt-2">
                  Work one artifact at a time. The tabs preserve the full chain without forcing the
                  page into a six-editor scroll trench.
                </p>
              </div>
              <%= if @project do %>
                <span class="workspace-shell__meta">
                  {artifact_completion_count(@project)}/6 core artifacts ready
                </span>
              <% end %>
            </div>

            <div class="artifact-tab-row">
              <button
                :for={section <- Projects.editable_sections()}
                type="button"
                phx-click="select_artifact"
                phx-value-artifact={section.key}
                class={artifact_tab_class(@active_artifact_key == section.key, artifact_present?(@project, section.key))}
              >
                <span>{section.label}</span>
                <span class="artifact-tab__state">
                  {if artifact_present?(@project, section.key), do: "Ready", else: "Missing"}
                </span>
              </button>
            </div>

            <%= if active_section do %>
              <.artifact_editor
                snapshot={@project || %{artifact_presence: %{}}}
                section={active_section}
                artifact_values={@artifact_values}
              />
            <% else %>
              <p class="panel-copy mt-6">Open a project to start editing artifacts.</p>
            <% end %>
          </section>

          <div class="dashboard-main__split">
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

          <section class="panel-shell">
            <p class="eyebrow">Model Settings</p>
            <p class="panel-copy mt-3">
              These settings drive the next run. Change them here, then rerun the phase you care about.
            </p>

            <.form for={%{}} as={:settings} phx-change="update_settings" class="mt-5 space-y-4">
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
          </div>
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
    |> assign(:run_states, %{})
    |> assign(:run_order, [])
    |> assign(:selected_run_id, nil)
    |> assign(:running_phases, MapSet.new())
    |> assign(:active_artifact_key, @default_artifact_key)
  end

  defp assign_project(socket, snapshot) do
    active_artifact_key =
      preferred_artifact_key(snapshot, socket.assigns[:active_artifact_key] || @default_artifact_key)

    socket
    |> assign(:project, snapshot)
    |> assign(:artifact_values, snapshot.artifact_values)
    |> assign(:phase_specs, Projects.phase_specs(snapshot))
    |> assign(:active_artifact_key, active_artifact_key)
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

  defp maybe_subscribe(socket, project_dir) do
    project_dir =
      case String.trim(project_dir || "") do
        "" -> nil
        value -> Path.expand(value)
      end

    previous = socket.assigns.subscribed_project_dir

    cond do
      previous == project_dir ->
        socket

      previous && connected?(socket) ->
        :ok = PhaseEvents.unsubscribe(previous)
        subscribe_if_present(socket, project_dir)

      true ->
        subscribe_if_present(socket, project_dir)
    end
  end

  defp subscribe_if_present(socket, nil), do: assign(socket, :subscribed_project_dir, nil)

  defp subscribe_if_present(socket, project_dir) do
    if connected?(socket) do
      :ok = PhaseEvents.subscribe(project_dir)
    end

    assign(socket, :subscribed_project_dir, project_dir)
  end

  defp apply_phase_event(socket, event) do
    event = normalize_phase_event(event)
    existing = Map.get(socket.assigns.run_states, event.run_id)

    case {existing, event.status} do
      {%{status: :cancelled}, status} when status != :cancelled ->
        socket

      _ ->
        run_state = merge_run_state(existing, event)

        socket
        |> assign(:run_states, Map.put(socket.assigns.run_states, event.run_id, run_state))
        |> assign(:run_order, [
          event.run_id | Enum.reject(socket.assigns.run_order, &(&1 == event.run_id))
        ])
        |> maybe_select_run(event)
        |> update_running_phases(event)
        |> maybe_assign_snapshot(event)
        |> maybe_note_activity(event)
    end
  end

  defp normalize_phase_event(event) do
    %{
      run_id: Map.get(event, :run_id) || Map.get(event, "run_id") || PhaseEvents.new_run_id(),
      phase: Map.get(event, :phase) || Map.get(event, "phase") || "unknown",
      status: Map.get(event, :status) || Map.get(event, "status") || :running,
      kind: Map.get(event, :kind) || Map.get(event, "kind") || :progress,
      progress: clamp_progress(Map.get(event, :progress) || Map.get(event, "progress") || 0),
      message: Map.get(event, :message) || Map.get(event, "message") || "",
      at: Map.get(event, :at) || Map.get(event, "at") || timestamp(),
      snapshot: Map.get(event, :snapshot) || Map.get(event, "snapshot"),
      stage: Map.get(event, :stage) || Map.get(event, "stage")
    }
    |> demote_intermediate_terminal_event()
  end

  defp merge_run_state(nil, event) do
    %{
      run_id: event.run_id,
      phase: event.phase,
      phase_label: Projects.phase_label(event.phase),
      status: event.status,
      progress: event.progress,
      message: event.message,
      at: event.at,
      logs: [run_log_entry(event)]
    }
  end

  defp merge_run_state(existing, event) do
    %{
      existing
      | status: event.status,
        progress: event.progress,
        message: event.message,
        at: event.at,
        logs: append_log(existing.logs, run_log_entry(event))
    }
  end

  defp run_log_entry(event) do
    %{
      kind: event.kind,
      status: event.status,
      message: event.message,
      at: event.at
    }
  end

  defp append_log(logs, entry) do
    (logs ++ [entry])
    |> Enum.take(-80)
  end

  defp maybe_select_run(socket, event) do
    cond do
      socket.assigns.selected_run_id in [nil, event.run_id] ->
        assign(socket, :selected_run_id, event.run_id)

      event.status == :running and event.kind == :started ->
        assign(socket, :selected_run_id, event.run_id)

      true ->
        socket
    end
  end

  defp maybe_assign_snapshot(socket, %{status: :success, snapshot: snapshot})
       when is_map(snapshot) do
    assign_project(socket, snapshot)
  end

  defp maybe_assign_snapshot(socket, _event), do: socket

  defp maybe_note_activity(socket, %{status: :running}), do: socket

  defp maybe_note_activity(socket, %{status: :success, message: message}) do
    note_activity(socket, :success, message)
  end

  defp maybe_note_activity(socket, %{status: :cancelled, message: message}) do
    note_activity(socket, :cancelled, message)
  end

  defp maybe_note_activity(socket, %{status: :error, message: message}) do
    note_activity(socket, :error, message)
  end

  defp maybe_note_activity(socket, _event), do: socket

  defp update_running_phases(socket, %{phase: phase, status: :running}) do
    update(socket, :running_phases, &MapSet.put(&1, phase))
  end

  defp update_running_phases(socket, %{phase: phase, status: status})
       when status in [:success, :error, :cancelled] do
    update(socket, :running_phases, &MapSet.delete(&1, phase))
  end

  defp update_running_phases(socket, _event), do: socket

  defp ordered_runs(run_states, run_order) do
    Enum.map(run_order, &Map.get(run_states, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(6)
  end

  defp current_run(run_states, selected_run_id, run_order) do
    selected_run(run_states, selected_run_id) || List.first(ordered_runs(run_states, run_order))
  end

  defp selected_run(run_states, selected_run_id), do: Map.get(run_states, selected_run_id)

  defp workflow_groups(phase_specs) do
    Enum.map(@workflow_groups, fn group ->
      specs =
        Enum.map(group.phases, &find_phase_spec(phase_specs, &1))
        |> Enum.reject(&is_nil/1)

      Map.put(group, :specs, specs)
    end)
  end

  defp find_phase_spec(phase_specs, key), do: Enum.find(phase_specs, &(&1.key == key))

  defp phase_ready?(phase_specs, key) do
    case find_phase_spec(phase_specs, key) do
      %{ready: ready} -> ready
      _ -> false
    end
  end

  defp next_action(nil, _phase_specs, _running_phases) do
    %{
      kind: :message,
      label: "Open a project directory",
      description: "Load a DenarioEx project to unlock the workflow and artifact studio.",
      cta: "Open Project",
      disabled: true
    }
  end

  defp next_action(snapshot, phase_specs, running_phases) do
    spec =
      cond do
        not artifact_present?(snapshot, "idea") -> find_phase_spec(phase_specs, "get_idea")
        not artifact_present?(snapshot, "methodology") -> find_phase_spec(phase_specs, "get_method")
        not artifact_present?(snapshot, "results") -> find_phase_spec(phase_specs, "get_results")
        not artifact_present?(snapshot, "literature") -> find_phase_spec(phase_specs, "check_idea")
        snapshot.keywords_count == 0 -> find_phase_spec(phase_specs, "get_keywords")
        output_ready_count(snapshot) < 1 -> find_phase_spec(phase_specs, "get_paper")
        not artifact_present?(snapshot, "referee_report") -> find_phase_spec(phase_specs, "referee")
        true -> find_phase_spec(phase_specs, "research_pilot")
      end

    case spec do
      nil ->
        %{
          kind: :message,
          label: "No next action found",
          description: "The phase registry did not return a usable next step.",
          cta: "Unavailable",
          disabled: true
        }

      %{key: key} = resolved ->
        %{
          kind: :phase,
          key: key,
          label: resolved.label,
          description: next_action_copy(key),
          cta:
            if(MapSet.member?(running_phases, key), do: "#{resolved.label} Running", else: "Run #{resolved.label}"),
          disabled: MapSet.member?(running_phases, key) or not resolved.ready
        }
    end
  end

  defp next_action_copy("get_idea"),
    do: "Start by locking the paper idea before you spend cycles on methods or results."

  defp next_action_copy("get_method"),
    do: "The idea is present. Turn it into an experimental plan while the brief is still fresh."

  defp next_action_copy("get_results"),
    do: "The narrative is set. Generate the evidence chain and figure-ready findings next."

  defp next_action_copy("check_idea"),
    do: "Run novelty checking now so literature feedback shapes the paper before final drafting."

  defp next_action_copy("get_keywords"),
    do: "The core work exists. Extract taxonomy-backed keywords to sharpen discoverability."

  defp next_action_copy("get_paper"),
    do: "The inputs are ready. Draft the paper package and optionally compile the PDF."

  defp next_action_copy("referee"),
    do: "Push the current draft through a review pass and collect the sharpest critique."

  defp next_action_copy("research_pilot"),
    do: "Everything is mostly in place. Re-run the full chain to refresh the project coherently."

  defp next_action_copy(_phase),
    do: "Run the next workflow phase."

  defp active_section(active_artifact_key) do
    Enum.find(Projects.editable_sections(), &(&1.key == active_artifact_key))
  end

  defp preferred_artifact_key(nil, current_key), do: current_key || @default_artifact_key

  defp preferred_artifact_key(snapshot, current_key) do
    fallback = Enum.find(@artifact_keys, &(not artifact_present?(snapshot, &1))) || @default_artifact_key

    cond do
      current_key not in @artifact_keys -> fallback
      current_key == @default_artifact_key -> fallback
      true -> current_key
    end
  end

  defp artifact_present?(nil, _key), do: false
  defp artifact_present?(snapshot, key), do: Map.get(snapshot.artifact_presence, key, false)

  defp artifact_completion_count(nil), do: 0

  defp artifact_completion_count(snapshot) do
    Enum.count(snapshot.artifact_presence, fn {_key, present?} -> present? end)
  end

  defp output_ready_count(nil), do: 0

  defp output_ready_count(snapshot) do
    paper_outputs =
      Enum.count([snapshot.paper_tex_path, snapshot.paper_pdf_path], &is_binary/1)

    base = paper_outputs + if(snapshot.referee_log_path, do: 1, else: 0)
    base + if(snapshot.plot_paths != [], do: 1, else: 0)
  end

  defp project_completion(nil), do: 0

  defp project_completion(snapshot) do
    checkpoints = [
      artifact_present?(snapshot, "data_description"),
      artifact_present?(snapshot, "idea"),
      artifact_present?(snapshot, "methodology"),
      artifact_present?(snapshot, "results"),
      artifact_present?(snapshot, "literature"),
      snapshot.keywords_count > 0,
      output_ready_count(snapshot) > 0,
      artifact_present?(snapshot, "referee_report")
    ]

    round(Enum.count(checkpoints, & &1) / length(checkpoints) * 100)
  end

  defp project_slug(project_dir), do: Path.basename(project_dir)

  defp pulse_headline(snapshot, nil) do
    cond do
      output_ready_count(snapshot) > 0 -> "Outputs are taking shape"
      artifact_completion_count(snapshot) >= 3 -> "The paper backbone exists"
      true -> "The brief is loaded and ready to move"
    end
  end

  defp pulse_headline(_snapshot, %{status: :running} = current_run),
    do: "#{current_run.phase_label} is in motion"

  defp pulse_headline(_snapshot, %{status: :success} = current_run),
    do: "#{current_run.phase_label} finished cleanly"

  defp pulse_headline(_snapshot, %{status: :error} = current_run),
    do: "#{current_run.phase_label} needs attention"

  defp pulse_headline(_snapshot, %{status: :cancelled} = current_run),
    do: "#{current_run.phase_label} was cancelled"

  defp pulse_headline(_snapshot, current_run), do: "Latest run: #{current_run.phase_label}"

  defp pulse_copy(snapshot, nil) do
    "#{artifact_completion_count(snapshot)} of 6 editable artifacts are filled, with #{output_ready_count(snapshot)} output surfaces already available."
  end

  defp pulse_copy(_snapshot, %{status: :running}) do
    "The monitor is locked onto the current run. Stay here for progress, status, and retry controls."
  end

  defp pulse_copy(_snapshot, %{status: :success}) do
    "The latest run completed successfully. Use the monitor to inspect its log or retry with new settings."
  end

  defp pulse_copy(_snapshot, %{status: :error}) do
    "The latest run failed. Inspect the log, adjust the settings or artifacts, and retry from the same panel."
  end

  defp pulse_copy(_snapshot, %{status: :cancelled}) do
    "The latest run was cancelled before completion. Restart it when you are ready."
  end

  defp pulse_copy(_snapshot, _current_run) do
    "The latest run is available in the monitor with its full event history."
  end

  defp run_spotlight_label(%{status: :running}), do: "Current Run"
  defp run_spotlight_label(_run), do: "Latest Run"

  defp progress_orb_style(percent) do
    "background: conic-gradient(rgba(252,211,77,0.95) 0 #{percent}%, rgba(255,255,255,0.09) #{percent}% 100%)"
  end

  defp clamp_progress(progress) when is_integer(progress), do: min(max(progress, 0), 100)

  defp clamp_progress(progress) when is_float(progress),
    do: progress |> round() |> clamp_progress()

  defp clamp_progress(_progress), do: 0

  defp demote_intermediate_terminal_event(
         %{
           phase: phase,
           status: :success,
           kind: :finished,
           stage: stage
         } = event
       ) do
    if canonical_terminal_stage?(phase, stage) do
      event
    else
      %{event | status: :running, kind: :progress, progress: min(event.progress, 99)}
    end
  end

  defp demote_intermediate_terminal_event(event), do: event

  defp canonical_terminal_stage?(_phase, stage) when stage in [nil, ""], do: true

  defp canonical_terminal_stage?(phase, stage) when is_binary(stage) do
    String.starts_with?(stage, "#{phase}:")
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> to_string()
  end

  defp artifact_badge_class(true), do: "state-pill state-pill--ready"
  defp artifact_badge_class(false), do: "state-pill state-pill--missing"

  defp phase_button_class(true, false),
    do: "phase-button phase-button--disabled"

  defp phase_button_class(_disabled, true),
    do: "phase-button phase-button--running"

  defp phase_button_class(false, false),
    do: "phase-button"

  defp activity_tone_class(:success), do: "activity-pill activity-pill--success"
  defp activity_tone_class(:cancelled), do: "activity-pill activity-pill--cancelled"
  defp activity_tone_class(:error), do: "activity-pill activity-pill--error"
  defp activity_tone_class(:saved), do: "activity-pill activity-pill--saved"
  defp activity_tone_class(_tone), do: "activity-pill activity-pill--running"

  defp run_status_class(:success), do: "activity-pill activity-pill--success"
  defp run_status_class(:cancelled), do: "activity-pill activity-pill--cancelled"
  defp run_status_class(:error), do: "activity-pill activity-pill--error"
  defp run_status_class(_status), do: "activity-pill activity-pill--running"

  defp run_card_class(true), do: "run-card run-card--selected"
  defp run_card_class(false), do: "run-card"

  defp artifact_tab_class(true, true), do: "artifact-tab artifact-tab--active artifact-tab--ready"
  defp artifact_tab_class(true, false), do: "artifact-tab artifact-tab--active artifact-tab--missing"
  defp artifact_tab_class(false, true), do: "artifact-tab artifact-tab--ready"
  defp artifact_tab_class(false, false), do: "artifact-tab artifact-tab--missing"
end
