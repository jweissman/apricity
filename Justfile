logs:
  hl ./log/apricity.log -h process-id -h pid -h fiber-id -h object-id -h severity -F

spec:
  rspec \
    --format doc \
    --tag "~dind" \
    --fail-fast

self-test:
  apricot --verbose

test-examples:
  apricot --verbose -- ./example/{hello,redis,pg,blog,git}/

test: spec self-test test-examples