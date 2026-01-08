require "rspec"
require_relative "../config/environment"
require_relative "../lib/user"
require "active_record"

RSpec.describe User do
  before do
    db_config = if ENV["DATABASE_URL"]
                  Environment.db_config_from_env
                else
                  YAML.load_file("config/database.yml")
                end

    ActiveRecord::Base.establish_connection(db_config)
  end

  after do
    ActiveRecord::Base.connection.close
  end

  it "creates and retrieves a User record" do
    user = User.create(name: "Alice", email: "alice@example.com")
    retrieved_user = User.find(user.id)
    expect(retrieved_user.name).to eq("Alice")
    expect(retrieved_user.email).to eq("alice@example.com")
    expect(retrieved_user.name_upcased).to eq("ALICE")
  end
end
