# Apricity

A lightweight CI/CD pipeline runner for Ruby that executes jobs inside isolated Docker containers.

**Apricity** (noun): *the warmth of the sun in winter* — bringing warmth and clarity to your CI/CD pipelines.

## Features

- 🐳 **Docker-native execution** — Jobs run in isolated containers with configurable images
- 📊 **DAG-based scheduling** — Automatic dependency resolution with parallel execution
- 🔌 **Plugin system** — Extensible architecture for JUnit reports, SBOM generation, code coverage
- 🌐 **Web dashboard** — Real-time pipeline visualization with SSE-powered live updates
- 🖥️ **CLI runner** — Terminal UI for local development with live status
- 📦 **Artifact passing** — Share files between jobs via artifact inputs/outputs
- 🔀 **Matrix builds** — Fan-out jobs with strategy matrices
- ⚡ **Concurrent execution** — Run independent jobs in parallel

## Installation

```bash
gem install apricity
```

Or add to your Gemfile:

```ruby
gem 'apricity'
```

## Quick Start

### 1. Create a pipeline file

Create `apricity.yaml` in your project root:

```yaml
name: My Pipeline
actions:
  build:
    jobs:
      - test:
          runs-on: ruby:3.4
          name: Run Tests
          mounts:
            - source: .
              target: /work
              type: bind
          steps:
            - name: Install dependencies
              run: |
                bundle install
            - name: Run tests
              run: |
                bundle exec rspec
```

### 2. Run the pipeline

```bash
# Using the CLI
apricot apricity.yaml

# With verbose output
apricot --verbose apricity.yaml
```

### 3. Or start the web dashboard

```bash
bin/server
# Visit http://localhost:4567
```

## Pipeline Configuration

### Basic Structure

```yaml
name: Pipeline Name
actions:
  action_name:
    jobs:
      - job_name:
          runs-on: image:tag      # Docker image
          name: Human-readable name
          needs: [other_job]      # Dependencies
          mounts: [...]           # Bind mounts
          steps: [...]            # Execution steps
          inputs: [...]           # Input artifacts/values
          outputs: [...]          # Output artifacts/values
          conditions: [...]       # Conditional execution
          plugins: [...]          # Plugin hooks
          strategy:               # Matrix builds
            matrix:
              key: [val1, val2]
```

### Mounts

Bind-mount directories from the host into the container:

```yaml
mounts:
  - source: .           # Current directory
    target: /work       # Mount point in container
    type: bind
  - source: /var/run/docker.sock
    target: /var/run/docker.sock
    type: bind
```

### Artifacts

Pass files between jobs:

```yaml
# Producer job
outputs:
  - key: test-results
    type: artifact

# Consumer job
inputs:
  - key: test-results
    type: artifact
needs: [producer_job]
```

### Values

Pass simple key-value data between jobs:

```yaml
# In a step, write to $APRICITY_OUTPUT
steps:
  - name: Set version
    run: echo "VERSION=1.0.0" >> $APRICITY_OUTPUT

outputs:
  - key: VERSION
    type: value
```

### Matrix Builds

Fan out jobs across multiple configurations:

```yaml
strategy:
  matrix:
    ruby: ["3.2", "3.3", "3.4"]
    os: [ubuntu, alpine]
```

This creates 6 jobs (3 × 2), each with `MATRIX_RUBY` and `MATRIX_OS` environment variables.

### Conditions

Conditionally run jobs:

```yaml
conditions:
  - type: success
    node_id: "action::job_name"
  - type: equals
    key: DEPLOY_ENV
    value: production
```

### Plugins

Attach plugins to jobs for reporting and analysis:

```yaml
plugins:
  - uses: apricity/junit-reporter
    with:
      junit_report: rspec.xml
      artifact_key: test-outputs
  - uses: apricity/simplecov-reporter
    with:
      artifact_key: coverage
  - uses: apricity/sbom-reporter
    with:
      artifact_key: sbom
```

## Built-in Plugins

| Plugin | Description |
|--------|-------------|
| `apricity/junit-reporter` | Parses JUnit XML reports and annotates jobs with test results |
| `apricity/simplecov-reporter` | Extracts Ruby code coverage metrics |
| `apricity/sbom-reporter` | Parses CycloneDX SBOM files for dependency analysis |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Apricity                              │
├─────────────────────────────────────────────────────────────┤
│  CLI (Apricot)          │  Web UI (April)                   │
│  └─ TUI Renderer        │  └─ Sinatra + HTMX + SSE          │
├─────────────────────────────────────────────────────────────┤
│                     Run / EventStore                         │
│              (Event-sourced state management)                │
├─────────────────────────────────────────────────────────────┤
│  Pipeline               │  JobExecution                      │
│  ├─ Parser (YAML)       │  ├─ Orchestrator                   │
│  ├─ Reducer (→ Nodes)   │  ├─ Planner                        │
│  ├─ Graph (DAG)         │  ├─ StepExecutor                   │
│  └─ Runner (Scheduler)  │  └─ Collector                      │
├─────────────────────────────────────────────────────────────┤
│                      Plugin System                           │
│               (Event-driven hooks)                           │
├─────────────────────────────────────────────────────────────┤
│                     Model Layer                              │
│  (Pipeline, Action, Job, Step, Input, Output, etc.)         │
├─────────────────────────────────────────────────────────────┤
│                     Docker API                               │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

- **Model** — Immutable domain objects using Ruby 3.2+ `Data.define`
- **Pipeline::Parser** — Converts YAML to model objects
- **Pipeline::Reducer** — Lowers pipelines to executable nodes (handles matrix expansion)
- **Pipeline::Graph** — Analyzes dependencies, performs topological sorting
- **Pipeline::Runner** — Schedules and executes nodes with concurrency
- **JobExecution::Orchestrator** — Manages Docker container lifecycle for a single job
- **Run::State** — Event-sourced state reducer for UI updates
- **Plugins** — Hook into job events for custom behavior

## Web Dashboard

The web UI provides:

- **Pipeline overview** — List of configured pipelines with run buttons
- **Live DAG visualization** — See job dependencies and status in real-time
- **Streaming logs** — Terminal output via Server-Sent Events
- **Run history** — Browse past executions

Start the server:

```bash
bin/server
```

## Development

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rspec

# Run the test suite with Apricity itself
apricot apricity.yaml

# Start interactive console
bin/console
```

## Requirements

- Ruby 3.2+
- Docker

## License

MIT License — see [LICENSE.txt](LICENSE.txt)

## Contributing

Bug reports and pull requests are welcome on GitHub.
