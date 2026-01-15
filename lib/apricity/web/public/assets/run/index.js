import { createReducer } from "./reducer.js";
import { renderJobList } from "./render_job_list.js";
import { renderAnnotations } from "./render_annotations.js";
import { renderDag } from "./dag.js";
import { connectSSE } from "./sse.js";

const { id, pipeline, eventsUrl, dag } = window.ApricityRun;

// Initialize jobs from DAG nodes so sidebar renders immediately
// SSE events will update the status as they come in
const initialJobs = {};
for (const node of dag.nodes) {
  initialJobs[node.id] = {
    status: "pending",
    steps: {}  // Will be populated when JobStarted event arrives
  };
}

const run = {
  id,
  pipeline,
  dag,
  jobs: initialJobs,
  ui: {
    openSteps: new Set()
  },
  annotations: {},
  status: "pending"
};

window.run = run;

function render() {
  // Render annotations
  const annotationsEl = document.getElementById("annotations-list");
  if (annotationsEl) {
    annotationsEl.innerHTML = renderAnnotations(run.annotations);
    
    // Show the annotations section
    annotationsEl.classList.remove("hidden");
  } else {
    console.warn("annotations-list not found");
  }
  // Render job list immediately (synchronous)
  renderJobList(run);
  // DAG render is async - don't await it to keep UI responsive
  renderDag(dag, run.jobs);
  
  // Scroll selected job into view smoothly
  if (window.location.hash) {
    const jobId = decodeURIComponent(window.location.hash.slice(1));
    const jobHeading = document.getElementById(jobId);
    if (jobHeading) {
      // Small delay to ensure DOM is ready
      requestAnimationFrame(() => {
        jobHeading.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }
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
 