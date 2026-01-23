# frozen_string_literal: true

require "singleton"
require "sinatra/base"
require "zlib"
require "stringio"
require "erb"
require "nokogiri"
require "timeout"

require_relative "../run_store"
require_relative "../job_execution"
require_relative "../worker"

module Apricity
  module Web
    module MimeTypes
      MIME_TYPES = {
        ".html" => "text/html",
        ".htm" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".svg" => "image/svg+xml",
        ".xml" => "application/xml"
      }.freeze
    end

    # Helper methods for pipeline management
    module Pipelines
      DEFAULT_PIPELINES = %w[echo sleep vets-api-sbom vets-api-test].map do |example_name|
        path = File.expand_path(File.join(__dir__, "../../../example/#{example_name}/apricity.yaml"))
        Apricity::Model::Pipeline.from_file(path)
      end.freeze
      # ]
      # .map { |path| Apricity::Model::Pipeline.from_file(path) }.freeze

      def load_pipeline(slug)
        pipeline = settings.pipelines.find { |p| p.slug == slug }
        halt 404, "Pipeline #{slug} not found" unless pipeline
        pipeline
      end
    end

    # Helper methods for SBOM (Software Bill of Materials) handling
    module SBOM
      def generate_sbom_html(sbom_path, run_context: nil)
        require "nokogiri"

        file = File.open(sbom_path)
        doc = Nokogiri::XML(file)
        ns = { "cdx" => doc.root.namespace.href }

        @components = parse_components(doc, ns)

        # Add run context if available
        if run_context
          @run_id = run_context[:run_id]
          @pipeline_name = run_context[:pipeline_name]
          @pipeline_slug = run_context[:pipeline_slug]
        end

        file.close

        # Generate HTML
        erb_template = File.read(File.join(__dir__, "views", "sbom.erb"))
        ERB.new(erb_template).result(binding)
      end

      def parse_components(doc, namespace)
        doc.xpath("//cdx:component", namespace).map do |component_node|
          parse_component(component_node, namespace)
        end
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def parse_component(component_node, namespace)
        name = component_node.at_xpath("cdx:name", namespace)&.text || "unknown"
        version = component_node.at_xpath("cdx:version", namespace)&.text || "unknown"
        component_type = component_node["type"] || "unknown"

        licenses = []
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:id", namespace).map(&:text)
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:name", namespace).map(&:text)
        licenses += component_node.xpath("cdx:licenses/cdx:license/cdx:expression", namespace).map(&:text)

        { name:, version:, type: component_type, licenses: licenses.uniq }
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
    end

    # Helper methods for JUnit XML test report handling
    module JUnit
      def generate_junit_html(junit_path, run_context: nil)
        file = File.open(junit_path)
        doc = Nokogiri::XML(file)
        file.close

        @report = parse_junit_document(doc)

        # Add run context if available
        if run_context
          @run_id = run_context[:run_id]
          @pipeline_name = run_context[:pipeline_name]
          @pipeline_slug = run_context[:pipeline_slug]
        end

        erb_template = File.read(File.join(__dir__, "views", "junit.erb"))
        ERB.new(erb_template).result(binding)
      end

      # rubocop:disable Metrics/AbcSize
      def parse_junit_document(doc)
        suites = doc.xpath("//testsuite").map { |suite| parse_test_suite(suite) }

        # Calculate totals across all suites
        totals = {
          tests: suites.sum { |s| s[:tests] },
          failures: suites.sum { |s| s[:failures] },
          errors: suites.sum { |s| s[:errors] },
          skipped: suites.sum { |s| s[:skipped] },
          time: suites.sum { |s| s[:time] }
        }
        totals[:passed] = totals[:tests] - totals[:failures] - totals[:errors] - totals[:skipped]

        { suites:, totals: }
      end
      # rubocop:enable Metrics/AbcSize

      def parse_test_suite(suite)
        {
          name: suite["name"] || "Unknown Suite",
          tests: suite["tests"].to_i,
          failures: suite["failures"].to_i,
          errors: suite["errors"].to_i,
          skipped: suite["skipped"].to_i,
          time: suite["time"].to_f,
          test_cases: suite.xpath("testcase").map { |tc| parse_test_case(tc) }
        }
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def parse_test_case(testcase)
        name = testcase["name"] || "Unknown Test"
        classname = testcase["classname"] || ""
        time = testcase["time"].to_f
        file = testcase["file"]

        # Determine status and extract failure/error message
        failure = testcase.at_xpath("failure")
        error = testcase.at_xpath("error")
        skipped = testcase.at_xpath("skipped")

        status, message = if failure
                            [:failure, failure.text || failure["message"]]
                          elsif error
                            [:error, error.text || error["message"]]
                          elsif skipped
                            [:skipped, skipped["message"]]
                          else
                            [:passed, nil]
                          end

        { name:, classname:, time:, file:, status:, message: }
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
    end

    # Helper methods for Server-Sent Events (SSE) streaming
    module Streaming
      def format_sse_json(event_type, json, event_id)
        raise "Invalid event" unless event_type && json

        "id: #{event_id}\nevent: #{event_type}\ndata: #{json}\n\n"
      end

      def replay_stored_events(run, out)
        last_event_id = request.env["HTTP_LAST_EVENT_ID"].to_i
        events = Apricity::Run::EventStore.get_events_json(run.id)

        events.each_with_index do |event, idx|
          event_id = idx + 1
          next unless event_id > last_event_id

          out << format_sse_json(event_type_from_json(event), event, event_id) if event_id > last_event_id
        end

        events.size
      end

      # rubocop:disable Metrics/MethodLength
      def stream_events(run, out)
        current_id = replay_stored_events(run, out)

        queue = Queue.new
        subscriber = Apricity::Run::Subscriber[queue]
        Apricity::Run::Subscriptions.add_subscriber(run.id, subscriber)

        # when client disconnects, force-unblock the streaming loop
        out.callback do
          Apricity::Run::Subscriptions.remove_subscriber(run.id, subscriber)
          queue << :__close__
        end

        out.errback do
          Apricity::Run::Subscriptions.remove_subscriber(run.id, subscriber)
          queue << :__close__
        end

        streaming_loop(out, queue, current_id)
      rescue IOError, Errno::EPIPE
      # client disconnected
      ensure
        Apricity::Run::Subscriptions.remove_subscriber(run.id, subscriber) if subscriber
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      def streaming_loop(out, queue, start_id)
        current_id = start_id
        loop do
          event = begin
            Timeout.timeout(1) { queue.pop }
          rescue ThreadError, Timeout::Error
            nil
          end
          unless event
            sleep 0.25
            next
          end
          break if event == :__close__

          unless event.is_a?(String)
            warn "StreamingLoop: Invalid event received: #{event.inspect}"
            next
          end

          # current_id += 1
          type = event_type_from_json(event)
          next unless type

          begin
            Timeout.timeout(5) do
              out << format_sse_json(type, event, current_id += 1)
              out.flush if out.respond_to?(:flush)
            end
          rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Timeout::Error
            break
          end

          break send_close_and_finish(out) if type == "pipeline_finished"
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength

      def send_close_and_finish(out)
        out << "event: close\ndata: {}\n\n"
        out.close
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        # ignore
      end

      def event_type_from_json(json) = json && json[/"type":"([^"]+)"/, 1]
    end

    # Helper methods for the web interface
    # rubocop:disable Metrics/ModuleLength
    module Support
      def serve_interactive_artifact_route
        requested_path = params[:splat].first
        full_path = safe_artifact_path(requested_path)
        warn "Serving interactive artifact: #{full_path} (for requested path: #{requested_path})"
        serve_interactive_artifact(full_path, requested_path)
      end

      def serve_artifact_download_route
        artifact_path = params[:splat].first
        full_path = safe_artifact_path(artifact_path)
        warn "Serving artifact download: #{full_path} (for artifact path: #{artifact_path})"
        # File.join(Dir.pwd, ".apricity", artifact_path)
        halt 404, "Artifact not found" unless File.exist?(full_path)

        serve_artifact_file_or_directory(full_path)
      end

      def serve_artifact_file_or_directory(full_path)
        return send_file(full_path, disposition: :attachment) unless File.directory?(full_path)

        files = Dir.glob("#{full_path}/**/*").reject { |f| File.directory?(f) }
        return send_file(files.first, disposition: :attachment) if files.size == 1

        content_type "application/gzip"
        attachment "#{File.basename(full_path)}.tar.gz"
        read_archived_artifact(full_path)
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

      # rubocop:disable Metrics/AbcSize
      def safe_artifact_path(requested_path)
        root = File.expand_path(artifact_root)
        rp = requested_path.to_s.sub(%r{\A/+}, "") # drop leading "/"

        # If someone passed "data/artifacts/..." or "/data/artifacts/...", strip it
        root_no_slash = root.delete_suffix("/")
        rp = rp.sub(%r{\A#{Regexp.escape(root_no_slash)}/?}, "")
        rp = rp.delete_prefix("data/artifacts/") if root.end_with?("/data/artifacts")

        full_path = File.expand_path(File.join(root, rp))

        warn "Resolved artifact path: #{full_path} (requested: #{requested_path}, normalized: #{rp})"

        halt 403, "Access denied" unless full_path.start_with?("#{root}/")
        halt 404, "Not found" unless File.exist?(full_path)

        full_path
      end
      # rubocop:enable Metrics/AbcSize

      def mime_type_for(path)
        ext = File.extname(path).downcase
        MimeTypes::MIME_TYPES.fetch(ext, "application/octet-stream")
      end

      # def artifact_root = Apricity::JobExecution::ArtifactStore::DEFAULT_ROOT
      def artifact_root
        root = File.expand_path(ENV.fetch("APRICITY_ARTIFACT_ROOT") { File.join(Dir.pwd, ".apricity") })
        warn "Using artifact root: #{root}"
        root
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/MethodLength
      def serve_interactive_artifact(full_path, requested_path)
        # Extract run context from path (format: runs/<run_id>/artifacts/...)
        run_context = extract_run_context_from_path(requested_path)

        # Check for SBOM first (could be sbom.xml file or directory containing sbom.xml)
        sbom_path = if full_path.end_with?("sbom.xml")
                      full_path
                    elsif File.directory?(full_path) && File.exist?(File.join(full_path, "sbom.xml"))
                      File.join(full_path, "sbom.xml")
                    elsif File.exist?("#{full_path}.xml") && full_path.include?("sbom")
                      "#{full_path}.xml"
                    end

        if sbom_path
          content_type "text/html"
          return generate_sbom_html(sbom_path, run_context: run_context)
        end

        # Check for JUnit report (artifact must be keyed as 'junit')
        junit_path = detect_junit_path(full_path)
        if junit_path
          content_type "text/html"
          return generate_junit_html(junit_path, run_context: run_context)
        end

        if File.directory?(full_path)
          serve_interactive_index(full_path, requested_path)
        else
          # Serve file with appropriate content type
          content_type mime_type_for(full_path)
          send_file full_path
        end
      end

      def detect_junit_path(full_path)
        return nil unless full_path.include?("junit")

        if full_path.end_with?(".xml") && File.exist?(full_path)
          full_path
        elsif File.directory?(full_path)
          # Look for common JUnit filenames in the directory
          %w[junit.xml rspec.xml results.xml].each do |filename|
            candidate = File.join(full_path, filename)
            return candidate if File.exist?(candidate)
          end
          # Fall back to first XML file
          Dir.glob(File.join(full_path, "*.xml")).first
        elsif File.exist?("#{full_path}.xml")
          "#{full_path}.xml"
        end
      end

      # Extract run ID and pipeline info from artifact path
      def extract_run_context_from_path(path)
        # Path could be:
        # - "runs/<run_id>/artifacts/..." (URL style)
        # - Or actual filesystem path ending in runs/<run_id>/artifacts/...

        # Try to find the run ID pattern in the path
        if path =~ %r{runs/([^/]+)/}
          run_id = ::Regexp.last_match(1)
        else
          warn "Could not extract run_id from path: #{path}"
          return nil
        end

        run = Apricity::RunStore.instance.get_run(run_id)
        unless run
          warn "Run not found for ID: #{run_id}"
          return nil
        end

        pipeline = settings.pipelines.find { |p| p.slug == run.pipeline_slug }

        context = {
          run_id: run_id,
          pipeline_slug: run.pipeline_slug,
          pipeline_name: pipeline&.name || run.pipeline_slug
        }

        warn "Extracted context: #{context.inspect}"
        context
      rescue StandardError => e
        warn "Failed to extract run context from path #{path}: #{e.message}"
        nil
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/MethodLength

      def serve_interactive_index(full_path, requested_path)
        # If directory requested, try to serve index.html
        index_path = File.join(full_path, "index.html")
        return unless File.exist?(index_path)

        content_type "text/html"
        # Inject base tag to fix relative asset paths
        html_content = File.read(index_path)
        base_url = "/interactive/artifact/#{requested_path}/"
        # Insert <base> tag after <head> if not present
        if html_content.include?("<base")
          send_file index_path
        else
          html_content.sub(/<head>/i, "<head>\n  <base href=\"#{base_url}\">")
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
    # rubocop:enable Metrics/ModuleLength

    # Sinatra-based web interface for Apricity
    class April < Sinatra::Base
      include Pipelines
      include Streaming
      include SBOM
      include JUnit
      include Support

      configure do
        set :quiet, true
        set :pipelines, DEFAULT_PIPELINES
      end

      helpers do
        def pretty_status(status)
          # Colored circle indicators for clean, consistent look
          case status.to_sym
          when :running then "🟡"
          when :success then "🟢"
          when :failure then "🔴"
          # when :skipped then "⚪"
          else "⚪"
          end
        end

        def dag_data(pipeline)
          nodes = Pipeline::Lowerer.lower(pipeline)
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
        @runs = Apricity::RunStore.instance.list_runs.select { |r| r.pipeline_slug == params[:slug] }
        erb :runs, layout: false
      end

      get "/runs" do
        @runs = Apricity::RunStore.instance.list_runs

        # Simple limit for dashboard
        @runs = @runs.first(params[:limit].to_i) if params[:limit]

        # Explicit partial request (from dashboard) or standard XHR
        if params[:partial] == "true" || request.xhr?
          erb :runs, layout: false
        else
          erb :activity
        end
      end

      get "/runs/:id" do
        run_id = params[:id]
        @run = Apricity::RunStore.instance.get_run(run_id)
        @lease = begin
          Apricity::Worker::Registry.instance.lease_for_run(run_id)
        rescue StandardError
          nil
        end
        halt 404, "Run #{run_id} not found" unless @run

        pipeline_slug = @run.pipeline_slug
        @pipeline = settings.pipelines.find { |p| p.slug == pipeline_slug }

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

        events = Apricity::Run::EventStore.get_events_json(params[:id])

        # finished = events.any? { |e| e.type == :pipeline_finished }
        # finished = events.any? { |json| json.include?('"type":"pipeline_finished"') }
        finished = run.status != "running" && run.status != "pending"

        if finished
          stream do |out|
            events.each_with_index do |event, idx|
              # out << format_sse(event, idx + 1)
              out << format_sse_json(JSON.parse(event)["type"], event, idx + 1)
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
        run_id = Run::Performer.pipeline(pipeline)
        redirect "/runs/#{run_id}"
      end

      # Serve interactive artifact content (e.g., coverage HTML reports)
      get("/interactive/artifact/*") { serve_interactive_artifact_route }

      # Download artifact file or directory as tar.gz
      get("/artifacts/*") { serve_artifact_download_route }

      get "/workers" do
        @workers = Apricity::Worker::Registry.list_workers
        @leases = Apricity::Worker::Registry.list_leases

        erb :workers
      end

      get "/about" do
        @docker_version = Docker.version
        @apricity_version = Apricity::VERSION
        erb :about
      end

      get("/docs") { erb :docs }
    end
  end
end
