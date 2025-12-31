export function connectSSE(url, { onEvent }) {
  const es = new EventSource(url);

  es.onopen = () => console.log("SSE open");
  es.onerror = e => console.error("SSE error", e);

  const handler = e => {
    const event = JSON.parse(e.data);
    onEvent(event);
  };

  [
    "job_started",
    "step_started",
    "step_finished",
    "stdout_chunk",
    "stderr_chunk",
    "job_finished",
    "job_annotated",
    "pipeline_finished"
  ].forEach(type => {
    es.addEventListener(type, handler);
  });

  es.addEventListener("close", () => {
    console.log("SSE close");
    es.close();
  });

  return es;
}