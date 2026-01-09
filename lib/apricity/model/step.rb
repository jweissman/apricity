# frozen_string_literal: true

module Apricity
  module Model
    Step = Data.define(:name, :run, :uses, :with) do
      def initialize(name:, run: nil, uses: nil, with: {})
        super
      end

      def uses? = !!uses
    end
  end
end
