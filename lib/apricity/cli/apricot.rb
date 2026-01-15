# frozen_string_literal: true

module Apricity
  module CLI
    # Render strategies for Apricot CLI
    module Renderer
      def render_tui(state)
        system("clear") || system("cls")

        puts state.pipeline.name
        puts "-" * 40
        state.nodes.each_value do |node_state|
          render_node(node_state)
          render_node_steps(node_state) # if node_state.phase == :running
          render_node_annotations(node_state)
        end
        render_pipeline_annotations(state)
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
        pretty_id = node_state.id.split("::").last
        puts " #{status} #{pretty_id}".ljust(30) + " | #{duration&.round(2) || "--"}s"
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

      def render_node_annotations(node_state)
        return if node_state.annotations.empty?

        node_state.annotations.each do |key, value|
          render_annotation(key, value)
        end
      end

      def render_pipeline_annotations(state)
        return if state.annotations.empty?

        puts "\n Pipeline Annotations:"
        state.annotations.each do |key, value|
          render_annotation(key, value)
        end
      end

      def render_annotation(key, value)
        pretty_key = key.to_s.tr("_", " ").capitalize
        puts "  #{value.fetch(:_icon, "*")} #{pretty_key}"
        pretty_value = value.except(:_icon)
        pretty_value.each do |k, v|
          puts "    - #{k}: #{v}"
        end
      end
    end

    # Apricot TUI renderer
    class Apricot
      include Renderer

      def executed_successfully?(pipeline:, git_sha: nil, options: { verbose: false })
        run = Apricity::Run::Instance.create(pipeline, git_sha:)
        run_id = run.id
        result = execute(pipeline:, run:, options:)
        apricot_icon = result.passed? ? "🍑" : "🪰"
        puts "\n#{apricot_icon} Run #{run_id[..7]} Complete (in #{result.duration_seconds} seconds)"
        result.passed?
      end

      private

      def execute(pipeline:, run:, options: {})
        state = Apricity::Run::State.empty(pipeline)
        unless options[:verbose]
          # for liveness, start a separate thread to update the UI
          Thread.new do
            loop do
              sleep 0.1
              render_tui(state)
            end
          end
        end
        run.perform { state = handle_event(it, state, options:) }
      end

      # def start_ui_thread(state)

      # end

      def handle_event(event, state, options: { verbose: false })
        state = state.reduce(event)
        if options[:verbose]
          echo_event(event)
        else
          render_tui(state)
        end
        state
      end

      def echo_event(event)
        # puts event.pretty
        is_chunk = %i[stdout_chunk stderr_chunk].include?(event.type)
        unless is_chunk
          warn event.pretty.capitalize
          return
        end

        # print event.chunk
        # grey
        print "\e[90m#{event.chunk}\e[0m"
        # else
        #   puts event.pretty.capitalize
      end
    end
  end
end
