# frozen_string_literal: true

module Apricity
  # Analyzes job nodes to determine dependencies and execution order
  class PipelineGraph
    attr_reader :nodes, :dependencies

    def initialize(nodes)
      @nodes = nodes
      @producer = {}
      @dependencies = Hash.new { |h, k| h[k] = [] }

      @analyzed_dependencies = false
      @analyzed_producers = false
    end

    def analyze_producers
      nodes.each do |n|
        n.outputs.each do |out|
          raise "duplicate output #{out.key}" if @producer.key?(out.key)

          @producer[out.key] = n.id
        end
      end

      @analyzed_producers = true
      true
    end

    def analyze_dependencies
      nodes.each do |n|
        n.inputs.each do |inp|
          if (p = @producer[inp.key])
            @dependencies[n.id] << p
          end
        end
        n.needs.each do |need_job_name|
          need_node = nodes.find { |node| node.job_name == need_job_name }
          raise "unknown needed job #{need_job_name} for job #{n.job_name}" unless need_node

          @dependencies[n.id] << need_node.id
        end
        @dependencies[n.id].uniq!
      end

      @analyzed_dependencies = true
      true
    end

    def topological_sort
      analyze_producers unless @analyzed_producers
      analyze_dependencies unless @analyzed_dependencies

      ids = nodes.map(&:id)
      indegree = ids.to_h { |id| [id, 0] }

      @dependencies.each do |to, froms|
        froms.each { indegree[to] += 1 }
      end

      queue = ids.select { |id| indegree[id].zero? }
      order = []

      until queue.empty?
        id = queue.shift
        order << id

        @dependencies.each do |to, froms|
          next unless froms.include?(id)

          indegree[to] -= 1
          queue << to if indegree[to].zero?
        end
      end

      raise "cycle detected" unless order.size == ids.size

      # order
      nodes.select { |n| order.include?(n.id) }.sort_by { |n| order.index(n.id) }
    end
  end
end
