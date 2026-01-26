import { AnsiUp } from 'https://cdn.jsdelivr.net/npm/ansi_up@6.0.6/+esm'
import humanize from "./util/humanize.js";
import {
  renderStatusIcon,
  getStepIconBgClasses,
  getStepCardClasses,
  getStepHeaderClasses,
  getStepNameClasses,
  renderStatusBadge,
  renderSidebarStatusIcon,
  getSidebarStatusIconColor
} from "./render_components.js";


// Track what we've rendered to enable differential updates
let lastRenderedJobId = null;
let lastRenderedSnapshot = null;

// Track output lengths per step to enable incremental updates
// Exported so hydration can initialize it
export const stepOutputLengths = new Map();

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

export function formatDuration(seconds) {
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
  // Use shared component for sidebar icons
  return renderSidebarStatusIcon(status);
}

function statusIconColor(status) {
  // Use shared component for sidebar icon colors
  return getSidebarStatusIconColor(status);
}

function statusBadge(status) {
  // Use shared component for status badges
  return renderStatusBadge(status);
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

  return `<span class="text-xs text-frost-500 font-mono bg-frost-50 px-2 py-0.5 rounded">${vars}</span>`;
}
/**
 * Format job metadata (git SHA, etc.) for display.
 */
function formatJobMetadata(job) {
  if (!job.metadata || Object.keys(job.metadata).length === 0) {
    return '';
  }

  const badges = [];

  const git_sha = job.metadata['git-sha'];
  // Git SHA badge with click-to-copy
  if (git_sha) {
    const shortSha = git_sha.substring(0, 7);
    badges.push(`
      <button 
        onclick="copyToClipboard('${git_sha}', this)" 
        class="inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-md bg-frost-100 hover:bg-frost-200 text-frost-700 font-mono transition-colors group"
        title="Click to copy: ${git_sha}">
        <i class="fab fa-git-alt text-frost-500 group-hover:text-frost-700"></i>
        <span>${shortSha}</span>
        <i class="far fa-copy text-[10px] opacity-0 group-hover:opacity-100 transition-opacity"></i>
      </button>
    `);
  }

  return badges.join('');
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
  jobSidebar.className = "job-sidebar shrink-0 w-64 border-r border-frost-200 pr-5";
  jobSidebar.id = "job-sidebar";
  jobSidebar.innerHTML = `
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-xs font-semibold text-frost-600 uppercase tracking-wide flex items-center gap-2">
        <i class="fas fa-layer-group text-frost-400 text-[10px]"></i>
        Jobs
      </h3>
      <button 
        onclick="window.toggleSidebar?.()" 
        class="text-frost-400 hover:text-frost-600 md:hidden"
        title="Toggle sidebar">
        <i class="fas fa-bars text-sm"></i>
      </button>
    </div>
    <ul class="space-y-1.5">
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
                 class="block px-3 py-2.5 rounded-lg transition-all ${isActive ? 'bg-sun-50 shadow-sm ring-1 ring-sun-200/50' : 'hover:bg-frost-50'}">
                <div class="flex items-center justify-between gap-2">
                  <div class="flex items-center gap-2.5 min-w-0">
                    <span class="status-icon text-sm flex-shrink-0 ${statusColor}">${statusIcon(job.status)}</span>
                    <div class="flex flex-col min-w-0">
                      <span class="text-sm font-medium truncate ${isActive ? 'text-sun-700' : 'text-frost-700'}">${displayName}</span>
                      ${matrixBadge ? `<div class="mt-1">${matrixBadge}</div>` : ''}
                    </div>
                  </div>
                  ${jobDuration ? `<span class="text-xs text-frost-500 font-mono flex-shrink-0 tabular-nums">${jobDuration}</span>` : ''}
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
        const stdoutLen = (step.output.stdout || '').length;
        const stderrLen = (step.output.stderr || '').length;
        
        stepOutputLengths.set(`stdout-${stepId}`, stdoutLen);
        stepOutputLengths.set(`stderr-${stepId}`, stderrLen);
        
        // Reset AnsiUp instances since we rendered the full output fresh
        stepAnsiInstances.delete(`stdout-${stepId}`);
        stepAnsiInstances.delete(`stderr-${stepId}`);
        
        console.debug(`[Render] Tracked output for ${stepId}: stdout=${stdoutLen}b, stderr=${stderrLen}b`);
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
      const hasOutput = step.output && (step.output.stdout || step.output.stderr);

      // Update step card container classes using shared function
      stepEl.className = getStepCardClasses(step.status);
      // data-step-card attribute is already set in the initial HTML, no need to re-set

      // Update header classes using shared function
      const headerEl = stepEl.querySelector('.step-header');
      if (headerEl) {
        headerEl.className = getStepHeaderClasses(step.status, hasOutput);
      }

      // Update step name classes using shared function
      const nameEl = stepEl.querySelector('.step-name');
      if (nameEl) {
        nameEl.className = getStepNameClasses(step.status);
      }

      // Update status icon using shared rendering function
      const statusSpan = stepEl.querySelector('.step-status-icon');
      if (statusSpan) {
        // Update background using shared function
        statusSpan.className = `w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 step-status-icon ${getStepIconBgClasses(step.status)}`;
        
        // Update icon HTML using shared function - GUARANTEED consistent!
        statusSpan.innerHTML = renderStatusIcon(step.status);
      }

      // Update duration badge - include live elapsed time data attribute for running steps
      const durationSpan = stepEl.querySelector('.step-duration');
      if (durationSpan) {
        if (step.duration != null) {
          durationSpan.textContent = formatDuration(step.duration);
          durationSpan.classList.remove('hidden');
          delete durationSpan.dataset.startedAt;
        } else if (isRunning && step.startTime != null) {
          durationSpan.dataset.startedAt = String(step.startTime);
          durationSpan.classList.remove('hidden');
          // Timer will update the text
        } else {
          durationSpan.textContent = '';
          durationSpan.classList.add('hidden');
          delete durationSpan.dataset.startedAt;
        }
      }
    }

    // Terminal output is updated separately via updateTerminalOutput()
    // to avoid expensive re-renders during differential updates
  }
}

// Safe ID for use in HTML attributes/onclick handlers
// Exported for use in hydration
export function safeStepId(nodeId, stepName) {
  return `step-${nodeId}-${stepName}`.replace(/[^a-zA-Z0-9_-]/g, "_");
}

/**
 * Update terminal output incrementally - called on a timer, not on every event.
 * Only converts and appends NEW output, preserving ANSI state via per-step instances.
 * 
 * CRITICAL: Detects when output exists but tracking doesn't (after initial render)
 * to prevent double-appending or missing output.
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
        const currentTrackedLength = stepOutputLengths.get(`stdout-${stepId}`);
        
        // ✅ FIX: Detect when we have output but no tracking (fresh render/toggle)
        if (currentTrackedLength === undefined) {
          // Initialize tracking to match current state - don't append
          stepOutputLengths.set(`stdout-${stepId}`, fullStdout.length);
          // Also reset AnsiUp instance since the content is fresh
          stepAnsiInstances.delete(`stdout-${stepId}`);
          continue;
        }
        
        const lastLen = currentTrackedLength || 0;

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
        const currentTrackedLength = stepOutputLengths.get(`stderr-${stepId}`);
        
        // ✅ FIX: Detect when we have output but no tracking (fresh render/toggle)
        if (currentTrackedLength === undefined) {
          stepOutputLengths.set(`stderr-${stepId}`, fullStderr.length);
          stepAnsiInstances.delete(`stderr-${stepId}`);
          continue;
        }
        
        const lastLen = currentTrackedLength || 0;

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

/**
 * Toggle step output visibility WITHOUT full re-render
 * This is a surgical DOM update that preserves scroll, ANSI state, etc.
 */
window.toggleStepOutput = function (stepId) {
  const outputEl = document.getElementById(`step-${stepId}-output`);
  if (!outputEl) {
    console.warn(`Output element not found for ${stepId}`);
    return;
  }
  
  const button = outputEl.previousElementSibling; // The header button
  const chevron = button?.querySelector('.fa-chevron-down');
  
  const isCurrentlyOpen = !outputEl.classList.contains('hidden');
  
  if (isCurrentlyOpen) {
    // Close it
    run.ui.openSteps.delete(stepId);
    outputEl.classList.add('hidden');
    if (chevron) chevron.classList.remove('rotate-180');
    if (button) button.setAttribute('aria-expanded', 'false');
  } else {
    // Open it
    run.ui.openSteps.add(stepId);
    outputEl.classList.remove('hidden');
    if (chevron) chevron.classList.add('rotate-180');
    if (button) button.setAttribute('aria-expanded', 'true');
    
    // ✅ CRITICAL: Initialize output tracking when expanding for first time
    // This prevents updateTerminalOutput from double-appending
    const stdoutEl = document.getElementById(`stdout-${stepId}`);
    const stderrEl = document.getElementById(`stderr-${stepId}`);
    
    if (stdoutEl && !stepOutputLengths.has(`stdout-${stepId}`)) {
      // Read the actual content length from the pre-rendered output
      const currentContent = stdoutEl.textContent || '';
      stepOutputLengths.set(`stdout-${stepId}`, currentContent.length);
      console.debug(`[Toggle] Initialized stdout tracking for ${stepId}: ${currentContent.length} chars`);
    }
    
    if (stderrEl && !stepOutputLengths.has(`stderr-${stepId}`)) {
      const currentContent = stderrEl.textContent || '';
      stepOutputLengths.set(`stderr-${stepId}`, currentContent.length);
      console.debug(`[Toggle] Initialized stderr tracking for ${stepId}: ${currentContent.length} chars`);
    }
  }
  
  // ✅ NO FULL RE-RENDER - just toggle visibility!
  // This preserves:
  // - Terminal scroll positions
  // - AnsiUp instances and their state
  // - All other step states
  // - User's place in the UI
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

      // ✅ Use shared rendering functions - GUARANTEED consistency!
      const statusIconHtml = renderStatusIcon(step.status);
      const stepCardClasses = getStepCardClasses(step.status);
      const stepHeaderClasses = getStepHeaderClasses(step.status, hasOutput);
      const stepNameClasses = getStepNameClasses(step.status);
      const stepIconBgClasses = getStepIconBgClasses(step.status);

      return `
          <div class="group ${stepCardClasses}" data-step-card="${stepId}">
            <button 
              type="button"
              class="step-header ${stepHeaderClasses}"
              ${!isPending && hasOutput ? `onclick="toggleStepOutput('${stepId}')"` : ''}
              ${!isPending && hasOutput ? `aria-expanded="${isOpen}" aria-controls="step-${stepId}-output"` : ''}
            >
              <div class="flex items-center gap-3 min-w-0">
                <span class="w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 step-status-icon ${stepIconBgClasses}">
                  ${statusIconHtml}
                </span>
                <span class="step-name ${stepNameClasses} truncate">${name}</span>
                ${(step.duration || isRunning) ? `
                  <span class="step-duration text-xs text-frost-500 font-mono tabular-nums bg-frost-50 px-2 py-0.5 rounded" data-step-duration="${stepId}" ${isRunning && step.startTime ? `data-started-at="${step.startTime}"` : ''}>${step.duration ? formatDuration(step.duration) : ''}</span>
                ` : ''}
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                ${!isPending && hasOutput ? `<i class="fas fa-chevron-down text-frost-400 text-xs transition-transform ${isOpen ? 'rotate-180' : ''} group-hover:text-frost-600"></i>` : ''}
              </div>
            </button>
            ${!isPending && hasOutput ? `
              <div id="step-${stepId}-output" class="step-output ${isOpen ? "" : "hidden"} border-t border-frost-100" role="region">
                ${step.status === 'failure' && step.error ? `
                  <div class="bg-danger-50 border-l-4 border-danger-500 px-5 py-4">
                    <div class="flex items-start gap-3">
                      <div class="w-5 h-5 rounded-full bg-danger-100 flex items-center justify-center flex-shrink-0">
                        <i class="fas fa-exclamation text-danger-600 text-xs"></i>
                      </div>
                      <div class="min-w-0">
                        <h5 class="text-sm font-semibold text-danger-700 mb-1">Error</h5>
                        <p class="text-sm text-danger-600 font-mono break-all">${escapeHtml(step.error)}</p>
                      </div>
                    </div>
                  </div>
                ` : ''}
                <div class="terminal-output">
                  <pre id="stdout-${stepId}" class="stdout whitespace-pre-wrap break-words overflow-hidden">${renderAnsi(step.output.stdout)}</pre>
                  <pre id="stderr-${stepId}" class="stderr whitespace-pre-wrap break-words overflow-hidden ${step.output.stderr ? '' : 'hidden'}">${renderAnsi(step.output.stderr)}</pre>
                </div>
              </div>
            ` : ''}
          </div>`;
    }).join("")
    : `<div class="flex flex-col items-center justify-center py-16 px-6">
        <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-frost-50 to-frost-100 flex items-center justify-center mb-4 shadow-inner">
          <i class="fas fa-hourglass-start text-2xl text-frost-400"></i>
        </div>
        <p class="text-sm font-medium text-frost-600">Waiting to start...</p>
      </div>`;

  const displayName = formatJobName(nodeId, dagNodes);
  const node = dagNodes?.find(n => n.id === nodeId);
  const matrixInfo = node?.matrix && Object.keys(node.matrix).length > 0
    ? `<div class="flex items-center gap-2 mt-2">
         ${Object.entries(node.matrix).map(([k, v]) => 
           `<span class="text-xs text-frost-600 font-mono bg-frost-100 px-2 py-1 rounded">${k}=${v}</span>`
         ).join("")}
       </div>`
    : '';
  
  const metadataHtml = formatJobMetadata(job);

  jobEl.innerHTML = `
    <div class="space-y-4">
      <div class="flex items-start justify-between pb-3 border-b border-frost-200">
        <div class="flex-1 min-w-0">
          <h3 id="${nodeId}" class="text-lg font-semibold text-frost-800">${displayName}</h3>
          ${matrixInfo}
          ${metadataHtml ? `<div class="flex items-center gap-2 mt-2">${metadataHtml}</div>` : ''}
        </div>
        <div class="flex-shrink-0 ml-4">
          ${statusBadge(job.status)}
        </div>
      </div>
      
      <div class="space-y-2.5">
        ${stepsHtml}
      </div>
      
      ${job.artifacts && Object.keys(job.artifacts).length > 0 ? `
        <div class="mt-4 p-4 rounded-lg bg-frost-50/50 border border-frost-200">
          <h4 class="text-xs font-semibold text-frost-700 uppercase tracking-wide mb-3 flex items-center gap-2">
            <i class="fas fa-archive text-frost-500"></i>Artifacts
          </h4>
          <div class="space-y-2.5">
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
          const isJUnit = key === 'junit';

          return `
                <div class="flex items-center justify-between p-2 bg-white rounded border border-frost-200">
                  <div class="flex items-center gap-2 min-w-0">
                    <i class="fas fa-file-archive text-frost-400"></i>
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-frost-700">${key}</div>
                      <div class="text-xs text-frost-500 font-mono truncate">${fileName}</div>
                    </div>
                  </div>
                  <div class="flex items-center gap-2 flex-shrink-0">
                    ${isCoverage ? `
                      <a 
                        href="${viewUrl}" 
                        target="_blank"
                        class="inline-flex items-center px-2 py-1 text-xs font-medium text-white bg-sun-500 hover:bg-sun-600 rounded"
                        title="View coverage report">
                        <i class="fas fa-chart-line mr-1"></i>
                        View
                      </a>
                    ` : ''}
                    ${isSBOM ? `
                      <a 
                        href="${viewUrl}" 
                        target="_blank"
                        class="inline-flex items-center px-2 py-1 text-xs font-medium text-white bg-frost-700 hover:bg-frost-800 rounded"
                        title="View SBOM report">
                        <i class="fas fa-cube mr-1"></i>
                        View
                      </a>
                    ` : ''}
                    ${isJUnit ? `
                      <a 
                        href="${viewUrl}" 
                        target="_blank"
                        class="inline-flex items-center px-2 py-1 text-xs font-medium text-white bg-sun-600 hover:bg-sun-700 rounded"
                        title="View test results">
                        <i class="fas fa-flask mr-1"></i>
                        View
                      </a>
                    ` : ''}
                    <a 
                      href="${downloadUrl}" 
                      download
                      class="inline-flex items-center px-2 py-1 text-xs font-medium text-frost-700 bg-frost-100 hover:bg-frost-200 rounded"
                      title="Download artifact">
                      <i class="fas fa-download"></i>
                    </a>
                  </div>
                </div>
              `;
        }).join("")}
          </div>
        </div>
      ` : ''}
      
      ${job.annotations ? `
        <div class="mt-4 p-4 rounded-lg bg-frost-50/50 border border-frost-200">
          <h4 class="text-xs font-semibold text-frost-700 uppercase tracking-wide mb-3 flex items-center gap-2">
            <i class="fas fa-tags text-frost-500"></i>
            Annotations
          </h4>
          <div class="space-y-2.5">
            ${Object.entries(job.annotations)
        .map(([key, elements]) => `
                <div class="flex items-center justify-between p-2 bg-white rounded border border-frost-200">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="text-base flex-shrink-0">${elements._icon || '📋'}</span>
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-frost-700">${humanize(key)}</div>
                      <div class="text-xs text-frost-500 space-x-2">
                        ${Object.entries(elements)
            .filter(([k]) => k !== "_icon")
            .map(([k, v]) => `<span>${k}: <strong class="text-frost-700">${v}</strong></span>`)
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

// Copy to clipboard with visual feedback
window.copyToClipboard = function(text, button) {
  navigator.clipboard.writeText(text).then(() => {
    // Flash success animation
    button.classList.add('copied-flash');
    const originalHTML = button.innerHTML;
    button.innerHTML = '<i class="fas fa-check text-success-600 text-xs"></i><span class="text-success-600">Copied!</span>';
    
    setTimeout(() => {
      button.innerHTML = originalHTML;
      button.classList.remove('copied-flash');
    }, 1500);
  }).catch(err => {
    console.error('Failed to copy:', err);
  });
};
