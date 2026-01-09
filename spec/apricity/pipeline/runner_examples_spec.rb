# frozen_string_literal: true

require "apricity/plugins/junit_reporter"
require "apricity/plugins/simplecov_reporter"

module Apricity
  include Model
  include Model::Builders

  EXAMPLES = Dir.glob(File.join(__dir__, "../../../example/**/apricity.yaml"))
                .map { |f| File.expand_path(f) }
                .to_h { |f| [f, File.dirname(f)] }

  RSpec.describe Pipeline::Runner, :dind do
    before do
      Apricity.register_default_plugins
      Apricity.register_default_actions
    end

    EXAMPLES.each do |file, filename|
      describe "runs example pipeline: #{filename}" do
        let(:pipeline) { Apricity::Model::Pipeline.from_file(file) }

        it_behaves_like "a successful pipeline"
      end
    end
  end
end
