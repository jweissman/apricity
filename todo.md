# Features
- [x] SimpleCov aggregation across shards
- [x] Services (pg/redis)
- [x] Simple rails app w/ services block
- [x] Git checkout action
- [x] Cache action (dumb cache file)
- [x] Env injection

# Enhancements
- [x] Pwd artifact pathing (killed mktmpdir)
- [x] Surface artifacts in UI
- [x] Dis-aggregate artifacts for matrixed jobs so we can simplecov collate
- [x] Normalize annotations for nonmatrixed jobs
- [x] Inject git metadata into run + surface on ui

# To-do
- [~] Deployment
- [~] Persistence
- [~] Stabilization
  - [~] Worker run leases
  - [~] Heartbeats -- last_output_at
  - [ ] Step timeouts?
  - [ ] Buffer stdout/stderr
- [ ] Repo/ref cold start endpoint
- [ ] JUnit + coverage verification on a smaller repo first
- [ ] Consume JUnit xml to nice report like sbom?
- [ ] Minio/s3 for artifact store
- [ ] Secrets (env injection from fly secrets?)
- [ ] Tiny example app with services
- [ ] Check the JUnit aggregation looks fine for matrix/nonmatrixed jobs
- [~] Try vets-api
  - [x] spec/model passing
  - [x] spec/lib passing
  - [ ] all specs in spec/ passing
  - [ ] all modules

- [ ] Coverage graph over time
- [ ] Integration with GH
- [ ] SSH into container?
- [ ] Change threaded exec to async gem (new backend for scheduler)
- [ ] runs-on integration w/ gh??
- [ ] cold start flow (wrapper around git receive?)
- [ ] e2es for f/e
- [ ] Persist pipeline state so we don't _have_ to replay events if pipeline is finished?

# Bugs
- [x] Address network accumulation somehow? -- reaper _does_ seem to fix this!
- [x] Try to repair step timestamps/durations on the f/e

# Nice to have
- [ ] Git mirroring?