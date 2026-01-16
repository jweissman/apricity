import { createReducer } from "./reducer.js";
import { renderJobList, updateTerminalOutput } from "./render_job_list.js";
import { renderAnnotations } from "./render_annotations.js";
import { renderDag } from "./dag.js";
import { connectSSE } from "./sse.js";

const { id, pipeline, eventsUrl, dag } = window.ApricityRun;

// Track seen event IDs to prevent duplicates on SSE reconnect
const seenEventIds = new Set();

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

// Dynamic favicon based on build status
function updateFavicon(status) {
  const favicon = document.getElementById('favicon');
  if (!favicon) return;
  
  const colors = {
    pending: '%236366f1',   // indigo
    running: '%23f59e0b',   // amber
    success: '%2310b981',   // emerald
    failure: '%23ef4444'    // red
  };
  const color = colors[status] || colors.pending;
  
  // SVG circle favicon
  favicon.href = `data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='40' fill='${color}'/></svg>`;
}

function render() {
  // Update favicon based on overall status
  const jobs = Object.values(run.jobs);
  const overallStatus = jobs.every(j => j.status === 'success')
    ? 'success'
    : jobs.some(j => j.status === 'failure')
      ? 'failure'
      : jobs.some(j => j.status === 'running')
        ? 'running'
        : 'pending';
  updateFavicon(overallStatus);
  
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
}

// Initial render
render();

// Re-render on hash change (back/forward, clicking links)
window.addEventListener("hashchange", render);

// Debounce render to avoid excessive re-renders during rapid SSE events
let renderScheduled = false;
function scheduleRender() {
  if (renderScheduled) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    render();
  });
}

// Periodic terminal output update (separate from structural render)
// This handles stdout/stderr chunks without triggering full renders
let outputUpdateScheduled = false;
setInterval(() => {
  if (outputUpdateScheduled) return;
  outputUpdateScheduled = true;
  requestAnimationFrame(() => {
    outputUpdateScheduled = false;
    updateTerminalOutput(run);
  });
}, 150); // Update terminal output at most ~7 times per second

const reduce = createReducer(run, scheduleRender);

connectSSE(eventsUrl, {
  onEvent(event) {
    // Skip duplicate events (happens on SSE reconnect)
    if (event.id && seenEventIds.has(event.id)) {
      return;
    }
    if (event.id) {
      seenEventIds.add(event.id);
    }
    reduce(event);
  }
});
 