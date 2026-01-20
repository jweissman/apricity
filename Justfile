logs:
  hl ./log/apricity.log -h process-id -h pid -h fiber-id -h object-id -h severity -F

confirm-deps-running:
  docker version
  redis-cli ping

spec: confirm-deps-running
  rspec \
    --format doc \
    --tag "~dind" \
    --fail-fast

self-test:
  apricot --verbose

test-examples:
  apricot --verbose -- ./example/{hello,redis,pg,blog,git}/

test: spec self-test test-examples

dev-server:
  bundle exec puma -C config/puma.rb

dev-worker:
  bundle exec bin/worker

dev:
  bundle exec foreman start

kill:
  kill -9 $(lsof -i:4567 -t)