# frozen_string_literal: true

module Apricity
  module CLI
    # Apricot TUI renderer
    class Apricot
      def monitor_execution(pipeline:, git_sha: nil)
        run = Apricity::Run::Instance.create(pipeline, git_sha:)
        run_id = run.id
        puts "Starting Run #{run_id[..7]} for pipeline #{pipeline.name} at git sha #{git_sha}"
        state = Apricity::Run::State.empty(pipeline)
        result = run.perform do |event|
          state = handle_event(event, state)
        end
        apricot_icon = result.passed? ? "🍑" : "🪰"
        puts "\n#{apricot_icon} Run #{run_id[..7]} Complete (in #{result.duration_seconds} seconds)"
      end

      def handle_event(event, state)
        state = state.reduce(event)
        render_tui(state)

        is_chunk = %i[stdout_chunk stderr_chunk].include?(event.type)
        if is_chunk
          print event.chunk
        else
          puts event.pretty.capitalize
        end

        state
      end

      def render_tui(state)
        system("clear") || system("cls")

        puts state.pipeline.name
        puts "-" * 40
        state.nodes.each_value do |node_state|
          render_node(node_state)
          render_node_steps(node_state) # if node_state.phase == :running
        end
      end

      ICONS = {
        pending: "🟡",
        running: "🔵",
        skipped: "🟠",
        success: "🟢",
        failure: "🔴"
      }.freeze

      def pretty_status(status)
        case status
        when :success then ICONS[:success]
        when :failure then ICONS[:failure]
        when :skipped then ICONS[:skipped]
        when :pending then ICONS[:pending]
        when :running then ICONS[:running]

        else
          "unknown (#{status})"
        end
      end

      def pretty_node_state(phase, status)
        case phase
        when :pending then ICONS[:pending]
        when :running then ICONS[:running]
        when :skipped, :completed then pretty_status(status)
        else
          "unknown (#{phase}/#{status})"
        end
      end

      def render_node(node_state)
        status = pretty_node_state(node_state.phase, node_state.status)
        t0 = node_state.started_at
        t1 = node_state.finished_at || Time.now
        duration = (t1 - t0).round(2) if t0
        puts " #{status} #{node_state.name}".ljust(30) + " | #{duration&.round(2) || "--"}s"
      end

      def render_node_steps(node_state)
        node_state.step_states.each do |step_state|
          render_node_step(step_state)
        end
      end

      def render_node_step(step_state)
        status = step_state.status
        puts "    #{pretty_status(status&.to_sym || :pending)} #{step_state.name} ".ljust(30) +
             " | #{step_state.duration_seconds}s"
      end
    end
  end
end
