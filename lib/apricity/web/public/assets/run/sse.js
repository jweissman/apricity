export function connectSSE(url, { onEvent }) {
  const es = new EventSource(url);

  es.onopen = () => console.log("SSE connected");
  es.onerror = e => console.error("SSE error", e);

  const handler = e => {
    const event = JSON.parse(e.data);
    // Include the SSE event ID for deduplication on reconnect
    if (e.lastEventId) {
      event.id = e.lastEventId;
    }
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
    "pipeline_finished",
    "pipeline_annotated"
  ].forEach(type => {
    es.addEventListener(type, handler);
  });

  es.addEventListener("close", () => {
    console.warn("SSE close");
    es.close();
  });

  return es;
}