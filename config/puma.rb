# frozen_string_literal: true

# Keep it simple; tune later
max_threads = Integer(ENV.fetch("PUMA_MAX_THREADS", "16"))
min_threads = Integer(ENV.fetch("PUMA_MIN_THREADS", "0"))
threads min_threads, max_threads

port ENV.fetch("PORT", 8080)

# The important part:
# During shutdown, don't wait forever for long-lived SSE requests.
# shutdown_timeout Integer(ENV.fetch("PUMA_SHUTDOWN_TIMEOUT", "3"))

# Puma 6+ supports force_shutdown_after; Puma 7 should too.
force_shutdown_after Float(ENV.fetch("PUMA_FORCE_SHUTDOWN_AFTER", "3.0"))

# In dev this helps you see exceptions; optional
# stdout_redirect $stdout, $stderr, true
