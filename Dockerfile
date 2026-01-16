ARG RUBY_VERSION=3.4.7
FROM ruby:$RUBY_VERSION-slim as base

WORKDIR /app

# System deps you may need at runtime (keep minimal)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Bundler
RUN gem update --system --no-document && gem install -N bundler

FROM base as build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile* ./
# If you have a Gemfile.lock, this will become reproducible
RUN bundle config set path /usr/local/bundle && \
    bundle install

FROM base

# Create a real home dir that is writable
RUN useradd ruby --create-home --home-dir /home/ruby --shell /bin/bash
USER ruby:ruby

# Make bundler deterministic at runtime
ENV HOME=/home/ruby \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_APP_CONFIG=/home/ruby/.bundle

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=ruby:ruby . .

EXPOSE 8080
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "8080"]

# ARG RUBY_VERSION=3.4.7
# FROM ruby:$RUBY_VERSION-slim as base
# 
# # Rack app lives here
# WORKDIR /app
# 
# # Update gems and bundler
# RUN gem update --system --no-document && \
#     gem install -N bundler
# 
# 
# # Throw-away build stage to reduce size of final image
# FROM base as build
# 
# # Install packages needed to build gems
# RUN apt-get update -qq && \
#     apt-get install --no-install-recommends -y build-essential
# 
# # Install application gems
# COPY Gemfile* .
# RUN bundle install
# 
# 
# # Final stage for app image
# FROM base
# 
# # Run and own the application files as a non-root user for security
# RUN useradd ruby --home /app --shell /bin/bash
# USER ruby:ruby
# 
# # Copy built artifacts: gems, application
# COPY --from=build /usr/local/bundle /usr/local/bundle
# COPY --from=build --chown=ruby:ruby /app /app
# 
# # Copy application code
# COPY --chown=ruby:ruby . .
# 
# # Start the server
# EXPOSE 8080
# CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "8080"]
# 