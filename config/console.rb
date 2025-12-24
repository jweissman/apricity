# frozen_string_literal: true

# Override the default log level
def log_level(_)
  :debug
end

# Override the default output
def make_output(*_args)
  # file append for Console
  # Console::Logger.new
  Console::Output::Serialized.new(
    File.open("log/apricity.log", "a")
  )
  # Console::Output::Terminal.new($stdout)
end
