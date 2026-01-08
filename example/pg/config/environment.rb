module Environment
  def self.db_config_from_env
    return unless ENV["DATABASE_URL"]
  
    uri = URI.parse(ENV["DATABASE_URL"])
    database = ENV.fetch("POSTGRES_DB", uri.path.sub(%r{^/}, ""))
    {
      adapter:  "postgresql",
      host:     uri.host,
      port:     uri.port,
      database:,
      username: ENV["POSTGRES_USER"] || uri.user,
      password: ENV["POSTGRES_PASSWORD"] || uri.password
    }
  end
end