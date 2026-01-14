import humanize from "./util/humanize.js";

function formatDuration(seconds) {
  if (!seconds) return '';
  if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}m ${secs}s`;
}

function statusIcon(status) {
  return {
    running: "⏳",
    success: "✅",
    failure: "❌",
    pending: "⏸️",
    skipped: "⏭️"
  }[status] || "❔";
}

function statusBadge(status) {
  const colors = {
    running: "bg-amber-100 text-amber-700 border-amber-300 shadow-amber-100",
    success: "bg-emerald-100 text-emerald-700 border-emerald-300 shadow-emerald-100",
    failure: "bg-red-100 text-red-700 border-red-300 shadow-red-100",
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
  const pulseClass = status === 'running' ? 'animate-pulse-subtle' : '';
  return `<span class="text-xs px-3 py-1.5 rounded-full border font-medium shadow-sm ${colorClass} ${pulseClass}">${statusIcon(status)} ${label}</span>`;
}


/**
 * Format a job name for display using DAG node metadata.
 * For matrix jobs, shows "Job Name 1/4" style labels.
 */
function formatJobName(nodeId, dagNodes) {
  const node = dagNodes?.find(n => n.id === nodeId);
  
  if (!node) {
    // Fallback: extract job key from nodeId (after ::)
    return nodeId.split("::")[1] || nodeId;
  }
  
  const baseName = humanize(node.label);
  
  // Matrix job - show index
  if (node.matrixIndex) {
    return `${baseName} ${node.matrixIndex}/${node.matrixTotal}`;
  }
  
  return baseName;
}

/**
 * Format matrix variables for display in a compact form.
 */
function formatMatrixBadge(nodeId, dagNodes) {
  const node = dagNodes?.find(n => n.id === nodeId);
  
  if (!node?.matrix || Object.keys(node.matrix).length === 0) {
    return '';
  }
  
  const vars = Object.entries(node.matrix)
    .map(([k, v]) => `${k}=${v}`)
    .join(", ");
  
  return `<span class="text-[10px] text-gray-400 font-mono">${vars}</span>`;
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
  const dagNodes = run.dag?.nodes || [];

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
  jobSidebar.id = "job-sidebar";
  jobSidebar.innerHTML = `
    <div class="flex items-center justify-between mb-3">
      <h3 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Jobs</h3>
      <button 
        onclick="window.toggleSidebar?.()" 
        class="text-gray-400 hover:text-gray-600 transition-colors md:hidden"
        title="Toggle sidebar">
        <i class="fas fa-bars text-sm"></i>
      </button>
    </div>
    <ul class="space-y-1">
      ${Object.entries(run.jobs)
      .map(
        ([nodeId, job]) => {
          const isActive = selectedJobId === nodeId || (!selectedJobId && Object.keys(run.jobs)[0] === nodeId);
          const displayName = formatJobName(nodeId, dagNodes);
          const matrixBadge = formatMatrixBadge(nodeId, dagNodes);
          return `<li>
              <a href="#${encodeURIComponent(nodeId)}" 
                 class="flex items-center space-x-2 px-3 py-2 rounded-lg transition-colors ${isActive ? 'bg-blue-100 text-blue-700 font-medium' : 'hover:bg-gray-100 text-gray-600'}">
                <span class="text-base">${statusIcon(job.status)}</span>
                <div class="flex flex-col min-w-0">
                  <span class="text-sm truncate">${displayName}</span>
                  ${matrixBadge}
                </div>
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
    jobContent.appendChild(renderJob(job, nodeId, dagNodes));
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

function renderJob(job, nodeId, dagNodes) {
  const jobEl = document.createElement("div");
  jobEl.className = "job-card";

  // Show empty state for pending jobs with no steps
  const hasSteps = Object.keys(job.steps).length > 0;
  const stepsHtml = hasSteps 
    ? Object.entries(job.steps).map(([name, step]) => {
        const stepId = safeStepId(nodeId, name);
        const isOpen = run.ui.openSteps.has(stepId);
        const isPending = step.status === 'pending';
        const hasOutput = step.output && (step.output.stdout || step.output.stderr);
        
        return `
          <div class="rounded-lg border border-gray-200 overflow-hidden ${isPending ? 'opacity-60' : ''}">
            <div 
              class="flex items-center justify-between px-4 py-3 ${isPending ? 'bg-gray-50' : 'bg-white'} ${!isPending ? 'cursor-pointer hover:bg-gray-50' : ''} transition-colors"
              ${!isPending ? `onclick="toggleStepOutput('${stepId}')"` : ''}
            >
              <div class="flex items-center space-x-3">
                <span class="text-base">${statusIcon(step.status)}</span>
                <span class="text-sm font-medium ${isPending ? 'text-gray-500' : 'text-gray-700'}">${name}</span>
                ${step.duration ? `<span class="text-xs text-gray-500 font-mono">${formatDuration(step.duration)}</span>` : ''}
              </div>
              ${!isPending && hasOutput ? `<i class="fas fa-chevron-${isOpen ? 'up' : 'down'} text-gray-400 text-xs"></i>` : ''}
            </div>
            ${!isPending && hasOutput ? `
              <div id="step-${name}-output" class="step-output ${isOpen ? "" : "hidden"}">
                ${step.status === 'failure' && step.error ? `
                  <div class="bg-red-50 border-l-4 border-red-500 p-4">
                    <div class="flex items-start">
                      <i class="fas fa-exclamation-circle text-red-500 mt-0.5 mr-3"></i>
                      <div>
                        <h5 class="text-sm font-semibold text-red-800 mb-1">Error</h5>
                        <p class="text-sm text-red-700 font-mono">${escapeHtml(step.error)}</p>
                      </div>
                    </div>
                  </div>
                ` : ''}
                <div class="bg-gray-900 p-4 terminal-output max-h-96 overflow-auto rounded-b-lg">
                  <pre class="stdout text-gray-300 whitespace-pre-wrap break-all text-xs">${escapeHtml(step.output.stdout) || '<span class="text-gray-500 italic">No output yet</span>'}</pre>
                  ${step.output.stderr ? `<pre class="stderr text-red-400 whitespace-pre-wrap break-all mt-2 text-xs">${escapeHtml(step.output.stderr)}</pre>` : ''}
                </div>
              </div>
            ` : ''}
          </div>`;
      }).join("")
    : `<div class="text-center py-12 text-gray-400">
        <div class="w-16 h-16 mx-auto mb-4 rounded-full bg-gray-100 flex items-center justify-center">
          <i class="fas fa-hourglass-start text-2xl text-gray-300"></i>
        </div>
        <p class="text-sm font-medium text-gray-500">Waiting to start...</p>
        <p class="text-xs text-gray-400 mt-1">Steps will appear once the job begins</p>
      </div>`;

  const displayName = formatJobName(nodeId, dagNodes);
  const node = dagNodes?.find(n => n.id === nodeId);
  const matrixInfo = node?.matrix && Object.keys(node.matrix).length > 0
    ? `<div class="text-xs text-gray-500 font-mono mt-1">${Object.entries(node.matrix).map(([k, v]) => `${k}=${v}`).join(" • ")}</div>`
    : '';

  jobEl.innerHTML = `
    <div class="space-y-4">
      <div class="flex items-center justify-between pb-3 border-b border-gray-100">
        <div>
          <h3 id="${nodeId}" class="text-lg font-semibold text-gray-900">${displayName}</h3>
          ${matrixInfo}
        </div>
        ${statusBadge(job.status)}
      </div>
      
      <div class="space-y-2">
        ${stepsHtml}
      </div>
      
      ${job.artifacts && Object.keys(job.artifacts).length > 0 ? `
        <div class="mt-4 p-4 rounded-lg bg-blue-50 border border-blue-100">
          <h4 class="text-xs font-semibold text-blue-600 uppercase tracking-wider mb-3 flex items-center">
            <i class="fas fa-archive mr-2"></i>Artifacts
          </h4>
          <div class="space-y-2">
            ${Object.entries(job.artifacts)
              .map(([key, path]) => {
                // Extract relative path from full path (after .apricity/)
                const relativePath = path.includes('.apricity/') 
                  ? path.split('.apricity/')[1] 
                  : path;
                const downloadUrl = `/artifacts/${relativePath}`;
                const viewUrl = `/interactive/artifact/${relativePath}`;
                const fileName = relativePath.split('/').pop();
                const isCoverage = key === 'coverage' || key.includes('coverage');
                const isSBOM = key === 'sbom' || key.includes('sbom');
                
                return `
                <div class="flex items-center justify-between p-3 bg-white rounded border border-blue-200 hover:border-blue-400 transition-colors">
                  <div class="flex items-center space-x-3 min-w-0">
                    <i class="fas fa-file-archive text-blue-500 text-lg"></i>
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-gray-900">${key}</div>
                      <div class="text-xs text-gray-500 font-mono truncate">${fileName}</div>
                    </div>
                  </div>
                  <div class="flex items-center space-x-2 flex-shrink-0">
                    ${isCoverage ? `
                      <a 
                        href="${viewUrl}" 
                        target="_blank"
                        class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-white bg-green-600 hover:bg-green-700 rounded-md transition-colors"
                        title="View coverage report">
                        <i class="fas fa-chart-line mr-1.5"></i>
                        View Report
                      </a>
                    ` : ''}
                    ${isSBOM ? `
                      <a 
                        href="${viewUrl}" 
                        target="_blank"
                        class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-md transition-colors"
                        title="View SBOM report">
                        <i class="fas fa-cube mr-1.5"></i>
                        View SBOM
                      </a>
                    ` : ''}
                    <a 
                      href="${downloadUrl}" 
                      download
                      class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-100 hover:bg-blue-200 rounded-md transition-colors"
                      title="Download artifact">
                      <i class="fas fa-download mr-1.5"></i>
                      Download
                    </a>
                    <button 
                      onclick="navigator.clipboard.writeText('${escapeHtml(path)}'); this.innerHTML='<i class=\\'fas fa-check\\'></i> Copied'; setTimeout(() => this.innerHTML='<i class=\\'fas fa-copy\\'></i>', 2000)" 
                      class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
                      title="Copy path">
                      <i class="fas fa-copy"></i>
                    </button>
                  </div>
                </div>
              `;
              }).join("")}
          </div>
        </div>
      ` : ''}
      
      ${job.annotations ? `
        <div class="mt-4 p-4 rounded-lg bg-indigo-50 border border-indigo-100">
          <h4 class="text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-3 flex items-center">
            <i class="fas fa-tags mr-2"></i>Annotations
          </h4>
          <div class="space-y-2">
            ${Object.entries(job.annotations)
              .map(([key, elements]) => `
                <div class="flex items-center justify-between p-3 bg-white rounded border border-indigo-200 hover:border-indigo-400 transition-colors">
                  <div class="flex items-center space-x-3 min-w-0">
                    <span class="text-lg flex-shrink-0">${elements._icon || '📋'}</span>
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-gray-900">${humanize(key)}</div>
                      <div class="text-xs text-gray-500 space-x-3">
                        ${Object.entries(elements)
                          .filter(([k]) => k !== "_icon")
                          .map(([k, v]) => `<span>${k}: <strong class="text-gray-800">${v}</strong></span>`)
                          .join("")}
                      </div>
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
