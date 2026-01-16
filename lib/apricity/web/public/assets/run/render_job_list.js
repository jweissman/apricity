import {AnsiUp} from 'https://cdn.jsdelivr.net/npm/ansi_up@6.0.6/+esm'
import humanize from "./util/humanize.js";


// Track what we've rendered to enable differential updates
let lastRenderedJobId = null;
let lastRenderedSnapshot = null;

// Track output lengths per step to enable incremental updates
const stepOutputLengths = new Map();

// Separate AnsiUp instance per step to maintain ANSI state across incremental updates
const stepAnsiInstances = new Map();

function getAnsiInstance(stepId) {
  if (!stepAnsiInstances.has(stepId)) {
    const instance = new AnsiUp();
    instance.use_classes = true;
    stepAnsiInstances.set(stepId, instance);
  }
  return stepAnsiInstances.get(stepId);
}

// Create a lightweight snapshot of structural data (no output content)
function createStructuralSnapshot(run) {
  const snapshot = { jobs: {} };
  for (const [jobId, job] of Object.entries(run.jobs)) {
    snapshot.jobs[jobId] = {
      status: job.status,
      steps: {}
    };
    for (const [stepName, step] of Object.entries(job.steps || {})) {
      snapshot.jobs[jobId].steps[stepName] = {
        status: step.status,
        hasOutput: !!(step.output && (step.output.stdout || step.output.stderr))
      };
    }
  }
  return snapshot;
}

function formatDuration(seconds) {
  if (!seconds) return '';
  if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}m ${secs}s`;
}

/**
 * Calculate total duration for a job from its steps.
 */
function getJobDuration(job) {
  if (!job.steps || Object.keys(job.steps).length === 0) return null;
  
  const totalDuration = Object.values(job.steps)
    .filter(step => step.duration)
    .reduce((sum, step) => sum + step.duration, 0);
  
  if (totalDuration === 0) return null;
  return formatDuration(totalDuration);
}

function statusIcon(status) {
  // Clean, minimal dot indicators
  return {
    running: "●",
    success: "●",
    failure: "●",
    pending: "○",
    skipped: "○"
  }[status] || "○";
}

function statusIconColor(status) {
  // Winter sun palette - cool, calm colors
  return {
    running: "text-amber-400",
    success: "text-emerald-400",
    failure: "text-rose-400",
    pending: "text-slate-300",
    skipped: "text-slate-400"
  }[status] || "text-slate-300";
}

function statusBadge(status) {
  // Soft, frosted badge styles
  const styles = {
    running: "bg-gradient-to-r from-amber-50 to-orange-50/80 text-amber-600 border-amber-200/60",
    success: "bg-gradient-to-r from-emerald-50 to-teal-50/80 text-emerald-600 border-emerald-200/60",
    failure: "bg-gradient-to-r from-rose-50 to-red-50/80 text-rose-600 border-rose-200/60",
    pending: "bg-slate-50 text-slate-500 border-slate-200/60"
  };
  const labels = {
    running: "Running",
    success: "Passed",
    failure: "Failed",
    pending: "Pending"
  };
  const icons = {
    running: '<i class="fas fa-circle-notch fa-spin text-amber-400"></i>',
    success: '<i class="fas fa-check-circle text-emerald-400"></i>',
    failure: '<i class="fas fa-times-circle text-rose-400"></i>',
    pending: '<i class="far fa-clock text-slate-400"></i>'
  };
  const styleClass = styles[status] || styles.pending;
  const label = labels[status] || status || "Pending";
  const icon = icons[status] || icons.pending;
  const pulseClass = status === 'running' ? 'animate-pulse-subtle' : '';
  const glowClass = status === 'running' ? 'animate-glow' : '';
  return `<span class="inline-flex items-center gap-2.5 text-xs px-4 py-2.5 rounded-full border font-medium shadow-sm ${styleClass} ${pulseClass} ${glowClass}">${icon} ${label}</span>`;
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
  
  return `<span class="text-[10px] text-slate-400 font-mono tracking-tight">${vars}</span>`;
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
  const selectedJobId = getSelectedJobId();
  const dagNodes = run.dag?.nodes || [];
  
  // Create lightweight snapshot for structural comparison
  const currentSnapshot = createStructuralSnapshot(run);
  
  // Check if we can do a differential update instead of full rebuild
  const needsFullRender = !lastRenderedSnapshot || 
                          lastRenderedJobId !== selectedJobId ||
                          hasStructuralChanges(lastRenderedSnapshot, currentSnapshot, selectedJobId);
  
  if (!needsFullRender) {
    // Differential update - just update statuses
    updateDifferential(run, selectedJobId, dagNodes);
    lastRenderedSnapshot = currentSnapshot;
    return;
  }
  
  // Full render needed
  const windowScrollY = window.scrollY;
  
  // Clear tracked output lengths for fresh render
  stepOutputLengths.clear();
  
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
  jobSidebar.className = "job-sidebar shrink-0 w-64 border-r border-slate-200/40 pr-6";
  jobSidebar.id = "job-sidebar";
  jobSidebar.innerHTML = `
    <div class="flex items-center justify-between mb-5">
      <h3 class="text-xs font-semibold text-slate-400 uppercase tracking-wider">Jobs</h3>
      <button 
        onclick="window.toggleSidebar?.()" 
        class="text-slate-400 hover:text-slate-600 transition-colors duration-200 md:hidden"
        title="Toggle sidebar">
        <i class="fas fa-bars text-sm"></i>
      </button>
    </div>
    <ul class="space-y-2">
      ${Object.entries(run.jobs)
      .map(
        ([nodeId, job]) => {
          const isActive = selectedJobId === nodeId || (!selectedJobId && Object.keys(run.jobs)[0] === nodeId);
          const displayName = formatJobName(nodeId, dagNodes);
          const matrixBadge = formatMatrixBadge(nodeId, dagNodes);
          const jobDuration = getJobDuration(job);
          const statusColor = statusIconColor(job.status);
          return `<li>
              <a href="#${encodeURIComponent(nodeId)}" 
                 class="flex items-center justify-between px-4 py-3 rounded-xl transition-all duration-200 ${isActive ? 'bg-gradient-to-r from-sky-100/80 to-blue-100/60 text-sky-700 font-medium shadow-sm border border-sky-200/40' : 'hover:bg-slate-100/60 text-slate-600'}">
                <div class="flex items-center space-x-3 min-w-0">
                  <span class="status-icon text-sm flex-shrink-0 ${statusColor}">${statusIcon(job.status)}</span>
                  <div class="flex flex-col min-w-0">
                    <span class="text-sm truncate">${displayName}</span>
                    ${matrixBadge}
                  </div>
                </div>
                ${jobDuration ? `<span class="text-[11px] text-slate-400 font-mono flex-shrink-0 tabular-nums">${jobDuration}</span>` : ''}
              </a>
            </li>`;
        }
      )
      .join("")}
    </ul>
  `;

  const jobContent = document.createElement("div");
  jobContent.className = "flex-1 min-w-0";

  const activeJobId = selectedJobId || Object.keys(run.jobs)[0];
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
  
  // Track output lengths for the rendered job so updateTerminalOutput doesn't double-append
  const activeJob = run.jobs[activeJobId];
  if (activeJob) {
    for (const [stepName, step] of Object.entries(activeJob.steps || {})) {
      const stepId = safeStepId(activeJobId, stepName);
      if (step.output) {
        stepOutputLengths.set(`stdout-${stepId}`, (step.output.stdout || '').length);
        stepOutputLengths.set(`stderr-${stepId}`, (step.output.stderr || '').length);
        // Reset AnsiUp instances since we rendered the full output fresh
        stepAnsiInstances.delete(`stdout-${stepId}`);
        stepAnsiInstances.delete(`stderr-${stepId}`);
      }
    }
  }
  
  // Track what we rendered using lightweight snapshot
  lastRenderedJobId = selectedJobId;
  lastRenderedSnapshot = currentSnapshot;
  
  // Restore scroll position after re-render (use rAF to ensure layout is complete)
  requestAnimationFrame(() => {
    window.scrollTo(0, windowScrollY);
  });
}

// Check if structural changes require a full re-render (using lightweight snapshots)
function hasStructuralChanges(oldSnapshot, newSnapshot, selectedJobId) {
  // Different number of jobs
  const oldJobIds = Object.keys(oldSnapshot.jobs);
  const newJobIds = Object.keys(newSnapshot.jobs);
  if (oldJobIds.length !== newJobIds.length) return true;
  if (!oldJobIds.every(id => newJobIds.includes(id))) return true;
  
  // Check the selected job for structural changes
  const jobId = selectedJobId || newJobIds[0];
  const oldJob = oldSnapshot.jobs[jobId];
  const newJob = newSnapshot.jobs[jobId];
  
  if (!oldJob || !newJob) return true;
  
  // Different number of steps
  const oldStepNames = Object.keys(oldJob.steps);
  const newStepNames = Object.keys(newJob.steps);
  if (oldStepNames.length !== newStepNames.length) return true;
  if (!oldStepNames.every(name => newStepNames.includes(name))) return true;
  
  // Check if any step went from no-output to having output (needs output container)
  for (const stepName of newStepNames) {
    const oldStep = oldJob.steps[stepName];
    const newStep = newJob.steps[stepName];
    if (!oldStep.hasOutput && newStep.hasOutput) return true;
  }
  
  return false;
}

// Differential update - surgically update just what changed
function updateDifferential(run, selectedJobId, dagNodes) {
  const jobIds = Object.keys(run.jobs);
  const activeJobId = selectedJobId || jobIds[0];
  
  // Update overall status badge in header
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
  
  // Update sidebar job statuses
  for (const [nodeId, job] of Object.entries(run.jobs)) {
    const sidebarLink = document.querySelector(`a[href="#${CSS.escape(encodeURIComponent(nodeId))}"]`);
    if (sidebarLink) {
      const statusSpan = sidebarLink.querySelector('.status-icon');
      if (statusSpan) {
        statusSpan.className = `status-icon text-sm flex-shrink-0 ${statusIconColor(job.status)}`;
        statusSpan.innerHTML = statusIcon(job.status);
      }
    }
  }
  
  // Update the active job's steps
  const job = run.jobs[activeJobId];
  if (!job) return;
  
  for (const [stepName, step] of Object.entries(job.steps)) {
    const stepId = safeStepId(activeJobId, stepName);
    
    // Update step status icon - use data-step-card attribute
    const stepEl = document.querySelector(`[data-step-card="${stepId}"]`);
    if (stepEl) {
      const isPending = step.status === 'pending';
      const isRunning = step.status === 'running';
      
      // Update step card container styling (opacity for pending, ring for running)
      stepEl.classList.toggle('opacity-40', isPending);
      stepEl.classList.toggle('ring-2', isRunning);
      stepEl.classList.toggle('ring-amber-200/60', isRunning);
      stepEl.classList.toggle('ring-offset-2', isRunning);
      
      // Update header background color
      const headerEl = stepEl.querySelector('.step-header');
      if (headerEl) {
        headerEl.classList.toggle('bg-slate-50/30', isPending);
        headerEl.classList.toggle('bg-white', !isPending);
        headerEl.classList.toggle('cursor-pointer', !isPending);
        headerEl.classList.toggle('hover:bg-slate-50/50', !isPending);
      }
      
      // Update step name text color
      const nameEl = stepEl.querySelector('.step-name');
      if (nameEl) {
        nameEl.classList.toggle('text-slate-400', isPending);
        nameEl.classList.toggle('text-slate-700', !isPending);
      }
      
      const statusSpan = stepEl.querySelector('.step-status-icon');
      if (statusSpan) {
        statusSpan.className = `step-status-icon text-sm ${statusIconColor(step.status)}`;
        statusSpan.innerHTML = isRunning ? '<i class="fas fa-circle-notch fa-spin text-amber-400"></i>' : statusIcon(step.status);
      }
      
      // Update duration badge
      const durationSpan = stepEl.querySelector('.step-duration');
      if (durationSpan) {
        if (step.duration) {
          durationSpan.textContent = formatDuration(step.duration);
          durationSpan.classList.remove('hidden');
        }
      }
    }
    
    // Terminal output is updated separately via updateTerminalOutput()
    // to avoid expensive re-renders during differential updates
  }
}

// Safe ID for use in HTML attributes/onclick handlers
function safeStepId(nodeId, stepName) {
  return `step-${nodeId}-${stepName}`.replace(/[^a-zA-Z0-9_-]/g, "_");
}

/**
 * Update terminal output incrementally - called on a timer, not on every event.
 * Only converts and appends NEW output, preserving ANSI state via per-step instances.
 */
export function updateTerminalOutput(run) {
  const selectedJobId = getSelectedJobId();
  const jobIds = Object.keys(run.jobs);
  const activeJobId = selectedJobId || jobIds[0];
  
  const job = run.jobs[activeJobId];
  if (!job) return;
  
  for (const [stepName, step] of Object.entries(job.steps)) {
    if (!step.output) continue;
    
    const stepId = safeStepId(activeJobId, stepName);
    
    // Update stdout incrementally
    if (step.output.stdout) {
      const stdoutEl = document.getElementById(`stdout-${stepId}`);
      if (stdoutEl) {
        const fullStdout = step.output.stdout;
        const lastLen = stepOutputLengths.get(`stdout-${stepId}`) || 0;
        
        if (fullStdout.length > lastLen) {
          // Only convert the NEW portion
          const newChunk = fullStdout.slice(lastLen);
          const ansi = getAnsiInstance(`stdout-${stepId}`);
          const newHtml = ansi.ansi_to_html(newChunk);
          
          // Append to existing content
          stdoutEl.insertAdjacentHTML('beforeend', newHtml);
          stepOutputLengths.set(`stdout-${stepId}`, fullStdout.length);
        }
      }
    }
    
    // Update stderr incrementally
    if (step.output.stderr) {
      const stderrEl = document.getElementById(`stderr-${stepId}`);
      if (stderrEl) {
        stderrEl.classList.remove('hidden');
        
        const fullStderr = step.output.stderr;
        const lastLen = stepOutputLengths.get(`stderr-${stepId}`) || 0;
        
        if (fullStderr.length > lastLen) {
          const newChunk = fullStderr.slice(lastLen);
          const ansi = getAnsiInstance(`stderr-${stepId}`);
          const newHtml = ansi.ansi_to_html(newChunk);
          
          stderrEl.insertAdjacentHTML('beforeend', newHtml);
          stepOutputLengths.set(`stderr-${stepId}`, fullStderr.length);
        }
      }
    }
  }
}

window.toggleStepOutput = function (stepId) {
  if (run.ui.openSteps.has(stepId)) {
    run.ui.openSteps.delete(stepId);
  } else {
    run.ui.openSteps.add(stepId);
  }
  
  // Force full re-render when toggling steps (structural change)
  lastRenderedSnapshot = null;
  renderJobList(run);
};

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
        const isRunning = step.status === 'running';
        const hasOutput = step.output && (step.output.stdout || step.output.stderr);
        const statusColor = statusIconColor(step.status);
        
        return `
          <div class="rounded-2xl border border-slate-200/60 overflow-hidden transition-all duration-300 ${isPending ? 'opacity-40' : ''} ${isRunning ? 'ring-2 ring-amber-200/60 ring-offset-2' : ''} hover:border-slate-300/80" data-step-card="${stepId}">
            <div 
              class="step-header flex items-center justify-between px-5 py-4 ${isPending ? 'bg-slate-50/30' : 'bg-white'} ${!isPending ? 'cursor-pointer hover:bg-slate-50/50' : ''} transition-colors duration-200"
              ${!isPending ? `onclick="toggleStepOutput('${stepId}')"` : ''}
            >
              <div class="flex items-center space-x-3.5">
                <span class="step-status-icon text-sm ${statusColor}">${isRunning ? '<i class="fas fa-circle-notch fa-spin text-amber-400"></i>' : statusIcon(step.status)}</span>
                <span class="step-name text-sm font-medium ${isPending ? 'text-slate-400' : 'text-slate-700'}">${name}</span>
                <span class="step-duration text-xs text-slate-400 font-mono tabular-nums bg-slate-100/80 px-2.5 py-1 rounded-lg ${step.duration ? '' : 'hidden'}">${step.duration ? formatDuration(step.duration) : ''}</span>
              </div>
              ${!isPending && hasOutput ? `<i class="fas fa-chevron-${isOpen ? 'up' : 'down'} text-slate-400 text-xs transition-transform duration-300 cursor-pointer"></i>` : ''}
            </div>
            ${!isPending && hasOutput ? `
              <div id="step-${stepId}-output" class="step-output ${isOpen ? "" : "hidden"}">
                ${step.status === 'failure' && step.error ? `
                  <div class="bg-gradient-to-r from-rose-50 to-red-50/80 border-l-4 border-rose-300 p-5">
                    <div class="flex items-start">
                      <i class="fas fa-exclamation-circle text-rose-400 mt-0.5 mr-3"></i>
                      <div>
                        <h5 class="text-sm font-semibold text-rose-700 mb-1">Error</h5>
                        <p class="text-sm text-rose-600 font-mono">${escapeHtml(step.error)}</p>
                      </div>
                    </div>
                  </div>
                ` : ''}
                <div class="bg-gradient-to-b from-slate-900 to-slate-950 p-5 terminal-output max-h-96 overflow-y-auto overflow-x-hidden" style="border-radius: 0 0 1rem 1rem;">
                  <pre id="stdout-${stepId}" class="stdout whitespace-pre-wrap break-words text-xs leading-relaxed overflow-hidden">${renderAnsi(step.output.stdout)}</pre>
                  <pre id="stderr-${stepId}" class="stderr whitespace-pre-wrap break-words mt-4 text-xs leading-relaxed pt-4 border-t border-slate-800 overflow-hidden ${step.output.stderr ? '' : 'hidden'}">${renderAnsi(step.output.stderr)}</pre>
                </div>
              </div>
            ` : ''}
          </div>`;
      }).join("")
    : `<div class="text-center py-20 text-slate-400">
        <div class="w-24 h-24 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-slate-100 to-slate-50 flex items-center justify-center shadow-inner">
          <i class="fas fa-hourglass-start text-4xl text-slate-300"></i>
        </div>
        <p class="text-sm font-medium text-slate-500">Waiting to start...</p>
        <p class="text-xs text-slate-400 mt-2">Steps will appear once the job begins</p>
      </div>`;

  const displayName = formatJobName(nodeId, dagNodes);
  const node = dagNodes?.find(n => n.id === nodeId);
  const matrixInfo = node?.matrix && Object.keys(node.matrix).length > 0
    ? `<div class="text-xs text-slate-500 font-mono mt-1">${Object.entries(node.matrix).map(([k, v]) => `${k}=${v}`).join(" • ")}</div>`
    : '';

  jobEl.innerHTML = `
    <div class="space-y-4">
      <div class="flex items-center justify-between pb-3 border-b border-slate-100">
        <div>
          <h3 id="${nodeId}" class="text-lg font-semibold text-slate-800">${displayName}</h3>
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
                <div class="flex items-center justify-between p-3 bg-white rounded-lg border border-blue-200/60 hover:border-blue-300 transition-colors">
                  <div class="flex items-center space-x-3 min-w-0">
                    <i class="fas fa-file-archive text-blue-500 text-lg"></i>
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-slate-800">${key}</div>
                      <div class="text-xs text-slate-500 font-mono truncate">${fileName}</div>
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
                      class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-slate-600 bg-slate-100 hover:bg-slate-200 rounded-md transition-colors"
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
        <div class="mt-6 p-5 rounded-xl bg-gradient-to-br from-indigo-50/80 via-violet-50/40 to-purple-50/30 border border-indigo-100/60">
          <h4 class="text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-4 flex items-center">
            <div class="w-5 h-5 rounded-md bg-gradient-to-br from-indigo-400 to-violet-500 flex items-center justify-center mr-2 shadow-sm">
              <i class="fas fa-tags text-white text-[8px]"></i>
            </div>
            Annotations
          </h4>
          <div class="space-y-2.5">
            ${Object.entries(job.annotations)
              .map(([key, elements]) => `
                <div class="flex items-center justify-between p-3.5 bg-white/90 rounded-xl border border-indigo-200/60 hover:border-indigo-300 hover:shadow-sm transition-all duration-150">
                  <div class="flex items-center space-x-3 min-w-0">
                    <span class="text-lg flex-shrink-0">${elements._icon || '📋'}</span>
                    <div class="min-w-0">
                      <div class="text-sm font-semibold text-slate-800">${humanize(key)}</div>
                      <div class="text-xs text-slate-500 space-x-3">
                        ${Object.entries(elements)
                          .filter(([k]) => k !== "_icon")
                          .map(([k, v]) => `<span>${k}: <strong class="text-slate-700">${v}</strong></span>`)
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

// Convert ANSI escape codes to HTML using ansi_up (for initial full renders)
function renderAnsi(text) {
  if (!text) return '';
  const ansi = new AnsiUp();
  ansi.use_classes = true;
  return ansi.ansi_to_html(text);
}

function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}
