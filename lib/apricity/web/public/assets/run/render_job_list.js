function statusIcon(status) {
  return {
    running: "⏳",
    success: "✅",
    failure: "❌"
  }[status] || "❔";
}

function statusBadge(status) {
  const colors = {
    running: "bg-amber-100 text-amber-700 border-amber-200",
    success: "bg-green-100 text-green-700 border-green-200",
    failure: "bg-red-100 text-red-700 border-red-200",
    pending: "bg-gray-100 text-gray-500 border-gray-200"
  };
  const labels = {
    running: "Running",
    success: "Passed",
    failure: "Failed",
    pending: "Pending"
  };
  const colorClass = colors[status] || colors.pending;
  const label = labels[status] || status || "Pending";
  return `<span class="text-xs px-2.5 py-1 rounded-full border font-medium ${colorClass}">${statusIcon(status)} ${label}</span>`;
}

function humanize(str) {
  return str
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// Get the current hash, properly decoded
function getSelectedJobId() {
  if (!window.location.hash) return null;
  try {
    return decodeURIComponent(window.location.hash.slice(1));
  } catch {
    return window.location.hash.slice(1);
  }
}

export function renderJobList(run) {
  const el = document.getElementById("job-list");
  el.innerHTML = "";

  const selectedJobId = getSelectedJobId();

  // Update status badge in header
  const overallStatus = Object.values(run.jobs).every(j => j.status === "success") 
    ? "success" 
    : Object.values(run.jobs).some(j => j.status === "failure") 
      ? "failure" 
      : Object.values(run.jobs).some(j => j.status === "running") 
        ? "running" 
        : "pending";
  const statusEl = document.getElementById("run-status");
  if (statusEl) {
    statusEl.innerHTML = statusBadge(overallStatus);
  }

  const jobSidebar = document.createElement("div");
  jobSidebar.className = "job-sidebar shrink-0 w-56 border-r border-gray-200 pr-4";
  jobSidebar.innerHTML = `
    <h3 class="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Jobs</h3>
    <ul class="space-y-1">
      ${Object.entries(run.jobs)
      .map(
        ([nodeId, job]) => {
          const isActive = selectedJobId === nodeId || (!selectedJobId && Object.keys(run.jobs)[0] === nodeId);
          return `<li>
              <a href="#${encodeURIComponent(nodeId)}" 
                 class="flex items-center space-x-2 px-3 py-2 rounded-lg transition-colors ${isActive ? 'bg-blue-100 text-blue-700 font-medium' : 'hover:bg-gray-100 text-gray-600'}">
                <span class="text-base">${statusIcon(job.status)}</span>
                <span class="text-sm truncate">${nodeId.split("::")[1] || nodeId}</span>
              </a>
            </li>`;
        }
      )
      .join("")}
    </ul>
  `;

  const jobContent = document.createElement("div");
  jobContent.className = "flex-1 min-w-0";

  for (const [nodeId, job] of Object.entries(run.jobs)) {
    if (selectedJobId && selectedJobId !== nodeId) continue;
    if (!selectedJobId && Object.keys(run.jobs)[0] !== nodeId) continue;
    jobContent.appendChild(renderJob(job, nodeId));
  }

  const flexContainer = document.createElement("div");
  flexContainer.className = "flex gap-6";

  flexContainer.appendChild(jobSidebar);
  flexContainer.appendChild(jobContent);

  el.appendChild(flexContainer);
}

window.toggleStepOutput = function (stepId) {
  if (run.ui.openSteps.has(stepId)) {
    run.ui.openSteps.delete(stepId);
  } else {
    run.ui.openSteps.add(stepId);
  }
  renderJobList(run);
};

// Safe ID for use in HTML attributes/onclick handlers
function safeStepId(nodeId, stepName) {
  return `step-${nodeId}-${stepName}`.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function renderJob(job, nodeId) {
  const jobEl = document.createElement("div");
  jobEl.className = "job-card";

  // Show empty state for pending jobs with no steps
  const hasSteps = Object.keys(job.steps).length > 0;
  const stepsHtml = hasSteps 
    ? Object.entries(job.steps).map(([name, step]) => {
        const stepId = safeStepId(nodeId, name);
        const isOpen = run.ui.openSteps.has(stepId);
        return `
          <div class="rounded-lg border border-gray-200 overflow-hidden">
            <div 
              class="flex items-center justify-between px-4 py-3 bg-gray-50 cursor-pointer hover:bg-gray-100 transition-colors"
              onclick="toggleStepOutput('${stepId}')"
            >
              <div class="flex items-center space-x-3">
                <span class="text-base">${statusIcon(step.status)}</span>
                <span class="text-sm font-medium text-gray-700">${name}</span>
              </div>
              <i class="fas fa-chevron-${isOpen ? 'up' : 'down'} text-gray-400 text-xs"></i>
            </div>
            <div id="step-${name}-output" class="step-output ${isOpen ? "" : "hidden"}">
              <div class="bg-gray-900 p-4 terminal-output max-h-96 overflow-auto rounded-b-lg">
                <pre class="stdout text-gray-300 whitespace-pre-wrap break-all text-xs">${escapeHtml(step.output.stdout) || '<span class="text-gray-500 italic">No output</span>'}</pre>
                ${step.output.stderr ? `<pre class="stderr text-red-400 whitespace-pre-wrap break-all mt-2 text-xs">${escapeHtml(step.output.stderr)}</pre>` : ''}
              </div>
            </div>
          </div>`;
      }).join("")
    : `<div class="text-center py-8 text-gray-400">
        <i class="fas fa-hourglass-start text-2xl mb-2 opacity-50"></i>
        <p class="text-sm">Waiting to start...</p>
      </div>`;

  const displayName = nodeId.split("::")[1] || nodeId;

  jobEl.innerHTML = `
    <div class="space-y-4">
      <div class="flex items-center justify-between pb-3 border-b border-gray-100">
        <h3 id="${nodeId}" class="text-lg font-semibold text-gray-900">${displayName}</h3>
        ${statusBadge(job.status)}
      </div>
      
      <div class="space-y-2">
        ${stepsHtml}
      </div>
      
      ${job.annotations ? `
        <div class="mt-4 p-4 rounded-lg bg-indigo-50 border border-indigo-100">
          <h4 class="text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-3">Annotations</h4>
          <div class="space-y-2">
            ${Object.entries(job.annotations)
              .map(([key, elements]) => `
                <div class="flex items-start space-x-2">
                  <span class="text-lg">${elements._icon || '📋'}</span>
                  <div>
                    <div class="font-medium text-gray-700 text-sm">${humanize(key)}</div>
                    <div class="text-xs text-gray-500 space-x-3">
                      ${Object.entries(elements)
                        .filter(([k]) => k !== "_icon")
                        .map(([k, v]) => `<span>${k}: <strong class="text-gray-800">${v}</strong></span>`)
                        .join("")}
                    </div>
                  </div>
                </div>
              `).join("")}
          </div>
        </div>
      ` : ''}
    </div>
  `;
  return jobEl;
}

function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}
