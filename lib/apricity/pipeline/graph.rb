# frozen_string_literal: true

module Apricity
  module Pipeline
    # Analyzes job nodes to determine dependencies and execution order
    class Graph
      # Internal class to perform topological sorting
      class Toposort
        attr_reader :nodes, :dependencies

        def initialize(nodes:, dependencies:)
          @nodes = nodes
          @dependencies = dependencies
        end

        def sorted_nodes
          setup
          sort_nodes
          raise "cycle detected" unless order.size == ids.size

          nodes.select { |n| order.include?(n.id) }
               .sort_by { |n| order.index(n.id) }
        end

        private

        def setup
          dependencies.each do |to, froms|
            froms.each { indegree[to] += 1 }
          end
        end

        def sort_nodes
          until queue.empty?
            id = queue.shift
            order << id

            dependencies.each do |to, froms|
              next unless froms.include?(id)

              indegree[to] -= 1
              queue << to if indegree[to].zero?
            end
          end
        end

        def ids = nodes.map(&:id)
        def indegree = @indegree ||= ids.to_h { |id| [id, 0] }
        def queue = @queue ||= ids.select { |id| indegree[id].zero? }
        def order = @order ||= []
      end

      attr_reader :nodes, :dependencies

      def initialize(nodes)
        @nodes = nodes
        @producer = {}
        @dependencies = Hash.new { |h, k| h[k] = [] }

        @analyzed_dependencies = false
        @analyzed_producers = false
      end

      def topological_sort
        analyze
        Toposort.new(nodes:, dependencies:).sorted_nodes
      end

      def analyze
        analyze_producers unless @analyzed_producers
        analyze_dependencies unless @analyzed_dependencies
      end

      private

      def analyze_producers
        nodes.each do |n|
          n.outputs.each do |out|
            warn "duplicate output #{out.key}" if @producer.key?(out.key)

            @producer[out.key] = n.id
          end
        end

        @analyzed_producers = true
      end

      def analyze_dependencies
        nodes.each do |n|
          analyze_node_inputs(n)
          analyze_node_needs(n)

          @dependencies[n.id].uniq!
        end

        @analyzed_dependencies = true
      end

      def analyze_node_inputs(node)
        node.inputs.each do |inp|
          if (p = @producer[inp.key])
            @dependencies[node.id] << p
          end
        end
      end

      def analyze_node_needs(node)
        node.needs.each do |need_job_name|
          # Find ALL nodes matching the needed job name (handles matrix jobs)
          need_nodes = nodes.select { |n| n.job_name.to_sym == need_job_name.to_sym }
          raise "unknown needed job #{need_job_name} for job #{node.job_name}" if need_nodes.empty?

          need_nodes.each do |need_node|
            @dependencies[node.id] << need_node.id
          end
        end
      end
    end
  end
end
