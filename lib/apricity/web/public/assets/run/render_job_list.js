function statusIcon(status) {
  return {
    running: "⏳",
    success: "✅",
    failure: "❌"
  }[status] || "❔";
}

function statusBadge(status) {
  const colors = {
    running: "bg-yellow-500/20 text-yellow-400 border-yellow-500/30",
    success: "bg-green-500/20 text-green-400 border-green-500/30",
    failure: "bg-red-500/20 text-red-400 border-red-500/30"
  };
  const labels = {
    running: "Running",
    success: "Passed",
    failure: "Failed"
  };
  const colorClass = colors[status] || "bg-gray-500/20 text-gray-400 border-gray-500/30";
  const label = labels[status] || status || "Pending";
  return `<span class="text-xs px-2 py-1 rounded-full border ${colorClass}">${statusIcon(status)} ${label}</span>`;
}

function humanize(str) {
  return str
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function renderJobList(run) {
  const el = document.getElementById("job-list");
  el.innerHTML = "";

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
  jobSidebar.className = "job-sidebar shrink-0";
  jobSidebar.innerHTML = `
    <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-4">Jobs</h3>
    <ul class="space-y-2">
      ${Object.entries(run.jobs)
      .map(
        ([nodeId, job]) => {
          const isActive = window.location.hash.slice(1) === nodeId || (!window.location.hash && Object.keys(run.jobs)[0] === nodeId);
          return `<li>
              <a href="#${nodeId}" 
                 class="flex items-center space-x-3 px-3 py-2 rounded-lg transition-colors ${isActive ? 'bg-blue-600/20 text-blue-400 border border-blue-500/30' : 'hover:bg-gray-800 text-gray-900 hover:text-gray-500'}">
                <span class="text-lg">${statusIcon(job.status)}</span>
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
    const hash = window.location.hash.slice(1);
    if (hash && hash !== nodeId) continue;
    if (!hash && Object.keys(run.jobs)[0] !== nodeId) continue;
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

function renderJob(job, nodeId) {
  const jobEl = document.createElement("div");
  jobEl.className = "job-card";

  jobEl.innerHTML = `
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 id="${nodeId}" class="text-lg font-semibold text-gray-800">${nodeId}</h3>
        ${statusBadge(job.status)}
      </div>
      
      <div class="space-y-2">
        ${Object.entries(job.steps)
      .map(([name, step]) => {
        const stepId = `step-${nodeId}-${name}`;
        const isOpen = run.ui.openSteps.has(stepId);

        return `
          <div class="rounded-lg border border-gray-700 overflow-hidden">
            <div 
              class="flex items-center justify-between px-4 py-3 bg-gray-800/50 cursor-pointer hover:bg-gray-800 hover:text-white transition-colors"
              onclick="toggleStepOutput('${stepId}')"
            >
              <div class="flex items-center space-x-3">
                <span class="text-lg">${statusIcon(step.status)}</span>
                <span class="text-sm font-medium">${name}</span>
              </div>
              <i class="fas fa-chevron-${isOpen ? 'up' : 'down'} text-gray-500 text-xs"></i>
            </div>
            <div id="step-${name}-output" class="step-output ${isOpen ? "" : "hidden"}">
              <div class="bg-gray-950 p-4 terminal-output max-h-96 overflow-auto">
                <pre class="stdout text-gray-300 whitespace-pre-wrap break-all">${escapeHtml(step.output.stdout) || '<span class="text-gray-600">No output</span>'}</pre>
                ${step.output.stderr ? `<pre class="stderr text-red-400 whitespace-pre-wrap break-all mt-2">${escapeHtml(step.output.stderr)}</pre>` : ''}
              </div>
            </div>
          </div>`;
      })
      .join("")}
      </div>
      
      ${job.annotations ? `
        <div class="mt-4 p-4 rounded-lg bg-gray-800/30 border border-gray-700">
          <h4 class="text-sm font-semibold text-gray-400 mb-3">Annotations</h4>
          <div class="space-y-2">
            ${Object.entries(job.annotations)
              .map(([key, elements]) => `
                <div class="flex items-start space-x-2">
                  <span class="text-lg">${elements._icon || '📋'}</span>
                  <div>
                    <div class="font-medium text-gray-500 text-sm">${humanize(key)}</div>
                    <div class="text-xs text-gray-400 space-x-3">
                      ${Object.entries(elements)
                        .filter(([k]) => k !== "_icon")
                        .map(([k, v]) => `<span>${k}: <strong class="text-gray-300">${v}</strong></span>`)
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
