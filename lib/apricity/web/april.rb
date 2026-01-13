# frozen_string_literal: true

require "singleton"
require "sinatra/base"
require "zlib"
require "stringio"

module Apricity
  # In-memory store for runs
  class RunStore
    include Singleton

    def initialize
      @runs = {}
    end

    def add_run(run) = @runs[run.id] = run
    def get_run(run_id) = @runs[run_id]
    def list_runs = @runs.values
  end

  module Web
    # Helper methods for the web interface
    module Support
      def load_pipeline(slug)
        pipeline = settings.pipelines.find { |p| p.slug == slug }
        halt 404, "Pipeline #{slug} not found" unless pipeline
        pipeline
      end

      def format_sse(event)
        payload = Apricity::JobExecution::EventSerializer.as_json(event)
        sse = "event: #{event.type}\ndata: #{payload}\n\n"
        puts "Formatted SSE: #{sse}"
        sse
      end

      def stream_events(run, out)
        queue = Queue.new
        subscriber = Apricity::Run::Subscriber[queue]
        Apricity::Run::EventStore.get_events(run.id).each { out << format_sse(it) }
        Apricity::Run::Subscriptions.add_subscriber(run.id, subscriber)
        begin
          streaming_loop(out, queue)
        rescue IOError, Errno::EPIPE
          # client disconnected
        ensure
          Apricity::Run::Subscriptions.remove_subscriber(params[:id], subscriber)
        end
      end

      def streaming_loop(out, queue)
        loop do
          event = queue.pop
          puts "Sending event #{event.type} to client"
          out << format_sse(event)
          next unless event.type == :pipeline_finished

          # puts "Pipeline finished, closing stream"
          out << "event: close\ndata: {}\n\n"
          out.close
          break
        end
      end

      def read_archived_artifact(full_path)
        # Create tar in memory first, then gzip it
        tar_io = StringIO.new
        Gem::Package::TarWriter.new(tar_io) do |tar|
          Dir.glob("#{full_path}/**/*").each do |file|
            next if File.directory?(file)

            add_file_to_archive(tar, file, full_path)
          end
        end

        # Now gzip the tar data
        tar_io.rewind
        gzip_data(tar_io)
      end

      def gzip_data(data_io)
        gzip_io = StringIO.new
        gz = Zlib::GzipWriter.new(gzip_io)
        gz.write(data_io.read)
        gz.close

        gzip_io.string
      end

      def add_file_to_archive(tar, file, full_path)
        relative_path = file.sub("#{full_path}/", "")
        stat = File.stat(file)
        tar.add_file(relative_path, stat.mode) do |tf|
          File.open(file, "rb") { |f| tf.write(f.read) }
        end
      end

      def safe_artifact_path(requested_path)
        # Normalize and validate path stays within .apricity
        artifact_root = File.join(Dir.pwd, ".apricity")
        full_path = File.expand_path(File.join(artifact_root, requested_path))

        # Security: ensure path is within artifact_root and doesn't escape
        halt 403, "Access denied" unless full_path.start_with?(artifact_root)

        halt 404, "Not found" unless File.exist?(full_path)
        full_path
      end

      def mime_type_for(path)
        case File.extname(path).downcase
        when ".html", ".htm" then "text/html"
        when ".css" then "text/css"
        when ".js" then "application/javascript"
        when ".json" then "application/json"
        when ".png" then "image/png"
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".gif" then "image/gif"
        when ".svg" then "image/svg+xml"
        when ".xml" then "application/xml"
        else "application/octet-stream"
        end
      end

      # Diagram generation helpers
      module Diagrams
        class << self
          def safe_id(id) = id.gsub("::", "_").tr("[", "_").tr("]", "_").tr("=", "_").tr(",", "_")

          def dag_json(nodes, graph)
            # Group nodes by job_name to calculate matrix indices
            {
              nodes: dag_nodes(nodes),
              edges: graph.dependencies.flat_map do |to_id, from_ids|
                from_ids.map { |from_id| { from: from_id, to: to_id } }
              end
            }
          end

          def dag_nodes(nodes)
            matrix_counts = nodes.group_by(&:job_name).transform_values(&:count)
            matrix_indices = Hash.new { |h, k| h[k] = 0 }

            nodes.map do |n|
              matrix_indices[n.job_name] += 1
              node_json(n, matrix_counts:, matrix_index: matrix_indices[n.job_name])
            end
          end

          def node_json(node, matrix_counts:, matrix_index:)
            total = matrix_counts[node.job_name]
            is_matrix = total > 1 || node.matrix&.any?

            {
              id: node.id,
              safeId: safe_id(node.id),
              label: node.job_name.to_s,
              matrix: node.matrix || {},
              matrixIndex: is_matrix ? matrix_index : nil,
              matrixTotal: is_matrix ? total : nil
            }.compact
          end
        end
      end
    end

    # Sinatra-based web interface for Apricity
    class April < Sinatra::Base
      include Support

      configure do
        set :quiet, true
        set :pipelines, [
          Apricity::Model::Pipeline.from_file("apricity.yaml"),
          Apricity::Model::Pipeline.from_file(".apricity-parallel.yaml"),
          # Apricity::Model::Pipeline.from_file("example/hello/apricity.yaml"),
          # Apricity::Model::Pipeline.from_file("example/redis/apricity.yaml"),
          # Apricity::Model::Pipeline.from_file("example/pg/apricity.yaml"),
          # Apricity::Model::Pipeline.from_file("example/git/apricity.yaml")
          *Dir.glob(File.join(__dir__, "../../../example/**/apricity.yaml"))
              .map { |f| Apricity::Model::Pipeline.from_file(f) }
        ]
      end

      helpers do
        def pretty_status(status)
          case status
          when :running then "⌛️"
          when :success then "✅"
          when :failure then "❌"
          when :skipped then "⏭️"
          else "❓"
          end
        end

        # def mermaid_dag(pipeline)
        #   nodes = Pipeline::Reducer.lower(pipeline)
        #   graph = Pipeline::Graph.new(nodes)
        #   graph.analyze
        #   Diagrams.mermaid_dag!(nodes, graph)
        # end

        def dag_data(pipeline)
          nodes = Pipeline::Reducer.lower(pipeline)
          graph = Pipeline::Graph.new(nodes)
          graph.analyze
          JSON.generate(Diagrams.dag_json(nodes, graph))
        end
      end

      get "/" do
        @pipelines = settings.pipelines
        @runs = Apricity::RunStore.instance.list_runs
        erb :index
      end

      get "/pipelines/:slug" do
        @pipeline = settings.pipelines.find { |p| p.slug == params[:slug] }
        halt 404, "Pipeline #{params[:slug]} not found" unless @pipeline

        erb :pipeline
      end

      get "/pipelines/:slug/runs" do
        @pipeline = load_pipeline(params[:slug])
        @runs = Apricity::RunStore.instance.list_runs.select { |r| r.pipeline.slug == params[:slug] }
        erb :runs, layout: false
      end

      get "/runs" do
        @runs = Apricity::RunStore.instance.list_runs
        @runs.map { |run| { id: run.id, status: run.status, started_at: run.started_at } }
        erb :runs, layout: false
      end

      get "/runs/:id" do
        run_id = params[:id]
        @run = Apricity::RunStore.instance.get_run(run_id)
        halt 404, "Run #{run_id} not found" unless @run

        @pipeline = @run.pipeline

        erb :run
      end

      get "/runs/:id/events", provides: "text/event-stream" do
        headers(
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        )
        run = Apricity::RunStore.instance.get_run(params[:id])
        halt 404, "Run #{params[:id]} not found" unless run

        if run.finished?
          stream do |out|
            Apricity::Run::EventStore.get_events(params[:id]).each do |event|
              out << format_sse(event)
            end
            out << "event: close\ndata: {}\n\n"
            out.close
          end
          return
        end

        stream(:keep_open) { stream_events(run, it) }
      end

      post "/pipelines/:slug/run" do
        pipeline = load_pipeline(params[:slug])
        run = Run::Instance.create(pipeline)
        RunStore.instance.add_run(run)

        Thread.new { run.perform }

        redirect "/runs/#{run.id}"
      end

      # Serve interactive artifact content (e.g., coverage HTML reports)
      get "/interactive/artifact/*" do
        requested_path = params[:splat].first
        full_path = safe_artifact_path(requested_path)

        if File.directory?(full_path)
          # If directory requested, try to serve index.html
          index_path = File.join(full_path, "index.html")
          if File.exist?(index_path)
            content_type "text/html"
            # Inject base tag to fix relative asset paths
            html_content = File.read(index_path)
            base_url = "/interactive/artifact/#{requested_path}/"
            # Insert <base> tag after <head> if not present
            if html_content.include?("<base")
              send_file index_path
            else
              html_with_base = html_content.sub(/<head>/i, "<head>\n  <base href=\"#{base_url}\">")
              html_with_base
            end
          end
        else
          # Serve file with appropriate content type
          content_type mime_type_for(full_path)
          send_file full_path
        end
      end

      # Download artifact file or directory as tar.gz
      get "/artifacts/*" do
        artifact_path = params[:splat].first
        full_path = File.join(Dir.pwd, ".apricity", artifact_path)

        halt 404, "Artifact not found" unless File.exist?(full_path)

        if File.directory?(full_path)
          # Check if directory contains only a single file
          files = Dir.glob("#{full_path}/**/*").reject { |f| File.directory?(f) }

          if files.size == 1
            # Single file - serve it directly
            send_file files.first, disposition: :attachment
          else
            # Multiple files - serve as tar.gz
            content_type "application/gzip"
            attachment "#{File.basename(full_path)}.tar.gz"
            read_archived_artifact(full_path)
          end
        else
          # Serve single file
          send_file full_path, disposition: :attachment
        end
      end
    end
  end
end
