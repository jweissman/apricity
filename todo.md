# Features
- [x] SimpleCov aggregation across shards
- [x] Services (pg/redis)
- [x] Simple rails app w/ services block
- [x] Git checkout step

# Enhancements
- [x] Pwd artifact pathing (killed mktmpdir)
- [x] Surface artifacts in UI

# To-do
- [ ] Dis-aggregate artifacts for matrixed jobs so we can simplecov collate
- [ ] Normalize annotations for nonmatrixed jobs
- [ ] Cache action (dumb cache file)
- [ ] Secrets (env injection, not vault)
- [ ] Tiny example app with services
- [ ] Try vets-api
- [ ] Persistence
- [ ] Coverage graph over time
- [ ] Integration with GH
- [ ] Deployment
- [ ] SSH into container?
- [ ] Change threaded exec to async gem?
- [ ] runs-on integration w/ gh??
- [ ] cold start flow (wrapper around git receive?)
- [ ] e2es for f/e
- [ ] Persist pipeline state so we don't _have_ to replay events if pipeline is finished?

# Bugs
- [ ] Try to repair step timestamps/durations on the f/e