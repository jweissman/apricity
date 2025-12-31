import { createReducer } from "./reducer.js";
import { renderJobList } from "./render_job_list.js";
import { renderDag } from "./dag.js";
import { connectSSE } from "./sse.js";

const { id, pipeline, eventsUrl, dag } = window.ApricityRun;

// Initialize jobs from DAG nodes so sidebar renders immediately
// SSE events will update the status as they come in
const initialJobs = {};
for (const node of dag.nodes) {
  initialJobs[node.id] = {
    status: "pending",
    steps: {}
  };
}

const run = {
  id,
  pipeline,
  dag,
  jobs: initialJobs,
  ui: {
    openSteps: new Set()
  }
};

window.run = run;

function render() {
  // Render job list immediately (synchronous)
  renderJobList(run);
  // DAG render is async - don't await it to keep UI responsive
  renderDag(dag, run.jobs);
}

// Initial render
render();

// Re-render on hash change (back/forward, clicking links)
window.addEventListener("hashchange", render);

const reduce = createReducer(run, render);

connectSSE(eventsUrl, {
  onEvent(event) {
    reduce(event);
  }
});
 