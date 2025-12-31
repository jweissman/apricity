export function createTerminal(container) {
  const term = new Terminal({
    cursorBlink: true,
    convertEol: true,
    theme: { background: "#000", foreground: "#fff" }
  });

  const fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(container);
  fitAddon.fit();

  let buffer = "";
  let timer = null;

  function flush() {
    term.write(buffer);
    buffer = "";
    timer = null;
  }

  function write(chunk) {
    buffer += chunk;
    if (!timer) timer = setTimeout(flush, 5);
  }

  return {
    handle(event) {
      if (event.type === "stdout_chunk") {
        write(event.data.chunk);
      } else if (event.type === "stderr_chunk") {
        write(`\x1b[31m${event.data.chunk}\x1b[0m`);
      } else if (event.type === "pipeline_finished") {
        write(`\r\nPipeline finished at ${event.at}\r\n`);
      }
    }
  };
}