export function createReducer(run, onChange) {
  return function reduce(event) {
    console.log('[Reducer]', event.type, event);
    
    switch (event.type) {
      case "job_started":
        // Initialize job with all steps from the event
        const steps = {};
        if (event.data && event.data.steps) {
          console.log('[Reducer] JobStarted with steps:', event.data.steps.length);
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
          startTime: Date.now()
        };
        break;

      case "stdout_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stdout += event.data.chunk;
        break;

      case "stderr_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stderr += event.data.chunk;
        break;

      case "step_finished":
        const step = run.jobs[event.node.id].steps[event.step.name];
        step.status = event.data.status;
        if (step.startTime) {
          step.duration = (Date.now() - step.startTime) / 1000;
        }
        if (event.data.error) {
          step.error = event.data.error;
        }
        break;

      case "job_finished":
        console.log('[Reducer] JobFinished:', event.data);
        run.jobs[event.node.id].status = event.data.status;
        if (event.data.artifacts) {
          console.log('[Reducer] JobFinished with artifacts:', event.data.artifacts);
          run.jobs[event.node.id].artifacts = event.data.artifacts;
        } else {
          console.log('[Reducer] JobFinished without artifacts');
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
        console.log("Pipeline finished with status:", run.status);
        break;
      
      case "pipeline_annotated":
        run.annotations = run.annotations || {};
        run.annotations = {
          ...run.annotations,
          ...event.data.annotations
        };
        console.log("Updated pipeline annotations:", run.annotations);
        break;
        
      default:
        console.warn("Unhandled event type:", event.type);
    }

    onChange();
  };
}