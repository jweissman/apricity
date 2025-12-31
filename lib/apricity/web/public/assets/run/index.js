import { createReducer } from "./reducer.js";
import { renderJobList } from "./render_job_list.js";
import { renderDag } from "./dag.js";
import { connectSSE } from "./sse.js";

const { id, pipeline, eventsUrl, dag } = window.ApricityRun;

const run = {
  id,
  pipeline,
  dag,
  jobs: {},
  ui: {
    openSteps: new Set()
  }
};

window.run = run;

// Initial DAG render (all pending)
renderDag(dag, run.jobs);

const reduce = createReducer(run, () => {
  renderJobList(run);
  renderDag(dag, run.jobs);
});

connectSSE(eventsUrl, {
  onEvent(event) {
    reduce(event);
  }
});
 