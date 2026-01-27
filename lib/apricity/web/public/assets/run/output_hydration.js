/**
 * Output hydration utilities for initializing step output from Redis tails.
 * 
 * Tails represent the last 32KB of output stored in Redis. This module merges
 * tail data into the run state structure before SSE connects, ensuring users
 * see existing output immediately.
 */

/**
 * Merge output tails into run state structure.
 * 
 * DEFENSIVE: Creates job/step structure if it doesn't exist yet.
 * This handles cases where we hydrate before SSE events arrive.
 * 
 * @param {Object} run - The run state object
 * @param {Object} tails - Tail data: { nodeId: { stepName: { stdout, stderr } } }
 * @returns {Object} Updated run state with output populated
 */
export function hydrateOutputFromTails(run, tails) {
  if (!tails || Object.keys(tails).length === 0) {
    console.debug('[Hydration] No tails to hydrate');
    return run;
  }

  console.log('[Hydration] Starting tail hydration with', Object.keys(tails).length, 'jobs');

  for (const [tailNodeId, steps] of Object.entries(tails)) {
    // Find matching job - could be under different key format
    // Tails might use "test" while jobs use "test::test"
    let matchingJobId = tailNodeId;
    
    if (!run.jobs[tailNodeId]) {
      // Try to find by prefix match (e.g., "benchmark::check" starts with "benchmark")
      const foundJobId = Object.keys(run.jobs).find(jobId => 
        jobId.startsWith(`${tailNodeId}::`) || jobId === tailNodeId
      );
      
      if (foundJobId) {
        matchingJobId = foundJobId;
        console.debug(`[Hydration] Matched tail node "${tailNodeId}" to job "${foundJobId}"`);
      } else {
        console.warn(`[Hydration] No matching job found for tail node "${tailNodeId}", skipping`);
        continue;
      }
    }

    // Ensure job exists
    if (!run.jobs[matchingJobId]) {
      console.warn(`[Hydration] Job ${matchingJobId} not found, creating it`);
      run.jobs[matchingJobId] = {
        status: 'pending',
        steps: {}
      };
    }

    // Ensure steps object exists
    if (!run.jobs[matchingJobId].steps) {
      run.jobs[matchingJobId].steps = {};
    }

    for (const [stepName, outputs] of Object.entries(steps)) {
      // Normalize step name - strip leading `:nodeId:` prefix if present
      // Tails might have ":test:Echo Hello" but events use "Echo Hello"
      const normalizedStepName = stepName.replace(/^:[^:]+:/, '');
      
      console.debug(`[Hydration] Processing step "${stepName}" → normalized: "${normalizedStepName}"`);
      
      // Ensure step exists - create if needed
      if (!run.jobs[matchingJobId].steps[normalizedStepName]) {
        console.debug(`[Hydration] Creating step ${normalizedStepName} in job ${matchingJobId}`);
        // Create step with 'success' status to ensure output is rendered
        // (pending steps don't show output in the UI)
        run.jobs[matchingJobId].steps[normalizedStepName] = {
          status: 'success',
          output: {}
        };
      }

      // Ensure output object exists
      if (!run.jobs[matchingJobId].steps[normalizedStepName].output) {
        run.jobs[matchingJobId].steps[normalizedStepName].output = {};
      }

      // Merge tail data (only if present and non-empty)
      if (outputs.stdout) {
        run.jobs[matchingJobId].steps[normalizedStepName].output.stdout = outputs.stdout;
        console.log(`[Hydration] Set stdout for ${matchingJobId}/${normalizedStepName}: ${outputs.stdout.length} bytes`);
      }
      if (outputs.stderr) {
        run.jobs[matchingJobId].steps[normalizedStepName].output.stderr = outputs.stderr;
        console.log(`[Hydration] Set stderr for ${matchingJobId}/${normalizedStepName}: ${outputs.stderr.length} bytes`);
      }
    }
  }

  console.log('[Hydration] Completed tail hydration');
  
  // Debug: Verify hydrated state
  Object.entries(run.jobs).forEach(([jobId, job]) => {
    Object.entries(job.steps || {}).forEach(([stepName, step]) => {
      if (step.output && (step.output.stdout || step.output.stderr)) {
        console.log(`[Hydration] Final state: ${jobId}/${stepName} has stdout=${step.output.stdout?.length || 0}b, stderr=${step.output.stderr?.length || 0}b`);
      }
    });
  });
  
  return run;
}

/**
 * Initialize output length tracking from hydrated state.
 * Must be called AFTER rendering so DOM elements exist.
 * 
 * This ensures that subsequent SSE chunks append correctly without duplication.
 * 
 * @param {Object} run - The run state (after hydration)
 * @param {Function} safeStepId - Function to generate step IDs
 * @param {Map} stepOutputLengths - The tracking map to populate
 */
export function initializeOutputTracking(run, safeStepId, stepOutputLengths) {
  for (const [nodeId, job] of Object.entries(run.jobs)) {
    if (!job.steps) continue;

    for (const [stepName, step] of Object.entries(job.steps)) {
      if (!step.output) continue;

      const stepId = safeStepId(nodeId, stepName);

      // Track stdout length
      if (step.output.stdout) {
        const length = step.output.stdout.length;
        stepOutputLengths.set(`stdout-${stepId}`, length);
        console.debug(`[Tracking] Initialized stdout for ${stepId}: ${length} bytes`);
      }

      // Track stderr length
      if (step.output.stderr) {
        const length = step.output.stderr.length;
        stepOutputLengths.set(`stderr-${stepId}`, length);
        console.debug(`[Tracking] Initialized stderr for ${stepId}: ${length} bytes`);
      }
    }
  }
}
