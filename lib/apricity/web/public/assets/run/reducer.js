function parseTimestamp(timestamp) {
  return new Date(timestamp).getTime();
}

export function createReducer(run, onChange) {
  return function reduce(event) {
    // Track if this is a structural change that needs a render
    let needsRender = true;
    
    switch (event.type) {
      case "job_started":
        // Initialize job with all steps from the event
        const steps = {};
        if (event.data && event.data.steps) {
          console.debug('[Reducer] JobStarted with steps:', event.data.steps.length);
          for (const step of event.data.steps) {
            steps[step.name] = {
              status: "pending",
              output: { stdout: "", stderr: "" }
            };
          }
        } else {
          console.warn('[Reducer] JobStarted missing steps data:', event.data);
        }
        run.jobs[event.node.id] = { status: "running", steps };
        break;

      case "step_started":
        run.jobs[event.node.id].steps[event.step.name] = {
          status: "running",
          output: { stdout: "", stderr: "" },
          startTime: parseTimestamp(event.at)
        };
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

      case "pipeline_finished":
        run.status = event.data.status;
        console.debug("Pipeline finished with status:", run.status);
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