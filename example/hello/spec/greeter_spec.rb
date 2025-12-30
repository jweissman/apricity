# frozen_string_literal: true

# A very simple hello world greeter to verify RSpec is working
class Greeter
  def greet
    "Hello, World!"
  end
end

RSpec.describe Greeter do
  subject(:greeter) { described_class.new }

  it "says hello" do
    expect(greeter.greet).to eq("Hello, World!")
  end
end
