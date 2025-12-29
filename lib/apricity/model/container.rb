# frozen_string_literal: true

module Apricity
  module Model
    Container = Data.define(:name, :version) do
      def to_s = "#{name}:#{version}"
    end
  end
end
