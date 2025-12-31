import { createReducer } from "./reducer.js";
import { renderJobList } from "./render_job_list.js";
import { createTerminal } from "./terminal.js";
import { connectSSE } from "./sse.js";

const { id, pipeline, eventsUrl } = window.ApricityRun;

const run = {
  id,
  pipeline,
  jobs: {},
  ui: {
    openSteps: new Set()
  }
};

window.run = run;

const reduce = createReducer(run, () => {
  renderJobList(run);
});

// const terminal = createTerminal(document.getElementById("terminal"));

connectSSE(eventsUrl, {
  onEvent(event) {
    reduce(event);
    // terminal.handle(event);
  }
});
 