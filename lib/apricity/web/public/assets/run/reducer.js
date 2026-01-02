export function createReducer(run, onChange) {
  return function reduce(event) {
    switch (event.type) {
      case "job_started":
        run.jobs[event.node.id] = { status: "running", steps: {} };
        break;

      case "step_started":
        run.jobs[event.node.id].steps[event.step.name] = {
          status: "running",
          output: { stdout: "", stderr: "" }
        };
        break;

      case "stdout_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stdout += event.data.chunk;
        break;

      case "stderr_chunk":
        run.jobs[event.node.id].steps[event.step.name].output.stderr += event.data.chunk;
        break;

      case "step_finished":
        run.jobs[event.node.id].steps[event.step.name].status = event.data.status;
        break;

      case "job_finished":
        run.jobs[event.node.id].status = event.data.status;
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