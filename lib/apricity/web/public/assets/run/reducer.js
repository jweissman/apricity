function parseTimestamp(timestamp) {
  return new Date(timestamp).getTime();
}

export function createReducer(run, onChange) {
  return function reduce(event) {
    console.debug("[Reducer] Event received:", event);
    // Track if this is a structural change that needs a render
    let needsRender = true;
    
    switch (event.type) {
      case "job_started":
        // Initialize job with all steps from the event
        // Preserve existing job and steps (e.g., from hydration) if present
        const existingJob = run.jobs[event.node.id] || {};
        const existingSteps = existingJob.steps || {};
        
        // Rebuild steps in the correct order from the event
        const steps = {};
        
        if (event.data && event.data.steps) {
          console.debug('[Reducer] JobStarted with steps:', event.data.steps.length);
          for (const step of event.data.steps) {
            // Check if step already exists (from hydration)
            if (existingSteps[step.name]) {
              // Preserve existing step with its hydrated output
              steps[step.name] = existingSteps[step.name];
              console.debug(`[Reducer] Preserving existing step: ${step.name}`);
            } else {
              // Create new step
              steps[step.name] = {
                status: "pending",
                output: { stdout: "", stderr: "" }
              };
            }
          }
        } else {
          console.warn('[Reducer] JobStarted missing steps data:', event.data);
        }
        run.jobs[event.node.id] = { ...existingJob, status: "running", steps };
        
        // Debug: Log the actual state after job_started
        if (run.jobs[event.node.id].steps['Echo Hello']) {
          const step = run.jobs[event.node.id].steps['Echo Hello'];
          console.log(`[Reducer] After job_started, Echo Hello output:`, 
            `stdout=${step.output?.stdout?.length || 0}b`,
            `stderr=${step.output?.stderr?.length || 0}b`);
        }
        break;

      case "step_started":
        // Preserve existing step data (e.g., hydrated output) if present
        const existingStep = run.jobs[event.node.id].steps[event.step.name] || {};
        run.jobs[event.node.id].steps[event.step.name] = {
          ...existingStep,
          status: "running",
          output: existingStep.output || { stdout: "", stderr: "" },
          startTime: parseTimestamp(event.at)
        };
        console.debug(`[Reducer] StepStarted: ${event.step.name}, preserved output: stdout=${existingStep.output?.stdout?.length || 0}b`);
        break;

      case "stdout_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stdout += event.data.chunk;
        // Don't trigger render for output chunks - too frequent
        needsRender = false;
        break;

      case "stderr_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stderr += event.data.chunk;
        // Don't trigger render for output chunks - too frequent
        needsRender = false;
        break;

      case "step_finished":
        console.log('[Reducer] StepFinished:', event);
        const step = run.jobs[event.node.id].steps[event.step.name];
        step.status = event.data.status;
        // Use duration from server if available, otherwise calculate from timestamps
        if (event.data.duration) {
          step.duration = event.data.duration;
        } else if (step.startTime) {
          const finishedAt = parseTimestamp(event.at);
          step.duration = (finishedAt - step.startTime) / 1000;
        }
        if (event.data.error) {
          step.error = event.data.error;
        }
        break;

      case "job_finished":
        console.debug('[Reducer] JobFinished:', event.data);
        run.jobs[event.node.id].status = event.data.status;
        if (event.data.artifacts) {
          console.warn('[Reducer] JobFinished with artifacts:', event.data.artifacts);
          run.jobs[event.node.id].artifacts = event.data.artifacts;
        } else {
          console.debug('[Reducer] JobFinished without artifacts');
        }
        break;

      case "job_annotated":
        run.jobs[event.node.id].annotations = {
          ...run.jobs[event.node.id].annotations,
          ...event.data.annotations
        };
        break;

      case "job_meta_updated":
        run.jobs[event.node.id].metadata = run.jobs[event.node.id].metadata || {};
        run.jobs[event.node.id].metadata[event.data.key] = event.data.value;
        console.debug(`[Reducer] Job metadata updated: ${event.data.key} = ${event.data.value}`);
        break;

      case "pipeline_finished":
        run.status = event.data.status;
        console.debug("Pipeline finished with status:", run.status, event);
        break;
      
      case "pipeline_annotated":
        run.annotations = run.annotations || {};
        run.annotations = {
          ...run.annotations,
          ...event.data.annotations
        };
        console.debug("Updated pipeline annotations:", run.annotations);
        break;
        
      default:
        console.warn("Unhandled event type:", event.type);
        needsRender = false;
    }

    if (needsRender) {
      onChange();
    }
  };
}