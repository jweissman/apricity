// Dynamic DAG rendering with Mermaid
// Updates node colors based on job status

const STATUS_STYLES = {
  running: "fill:#fef3c7,stroke:#f59e0b,stroke-width:2px",
  success: "fill:#d1fae5,stroke:#10b981,stroke-width:2px",
  failure: "fill:#fee2e2,stroke:#ef4444,stroke-width:2px",
  skipped: "fill:#e5e7eb,stroke:#9ca3af,stroke-width:2px",
  pending: "fill:#f3f4f6,stroke:#d1d5db,stroke-width:1px"
};

function nodeStatus(nodeId, jobs) {
  const job = jobs[nodeId];
  if (!job) return "pending";
  return job.status || "pending";
}

function safeId(id) {
  // Replace all characters that are invalid in Mermaid node IDs
  return id
    .replace(/::/g, "_")
    .replace(/\[/g, "_")
    .replace(/\]/g, "_")
    .replace(/=/g, "_")
    .replace(/\s+/g, "_");
}

function titleCase(str) {
  return str
    .replace(/_/g, " ")
    .replace(/\b\w/g, c => c.toUpperCase());
}

export function generateMermaidSyntax(dag, jobs) {
  const lines = ["graph LR"];
  
  // Add nodes with status-based styling and square shape
  dag.nodes.forEach((node) => {
    // Always compute safeId to ensure consistency
    const safe = safeId(node.id);
    // Use original ID for job status lookup
    const status = nodeStatus(node.id, jobs);
    const label = titleCase(node.label);
    // Square brackets for square/rectangular nodes
    lines.push(`  ${safe}["${label}"]`);
    lines.push(`  style ${safe} ${STATUS_STYLES[status]}`);
    // Add click handler to navigate to job (encode the ID for URL)
    lines.push(`  click ${safe} "#${encodeURIComponent(node.id)}"`);
  });
  
  // Add edges with arrow style
  dag.edges.forEach(edge => {
    lines.push(`  ${safeId(edge.from)} --> ${safeId(edge.to)}`);
  });
  
  return lines.join("\n");
}

let renderCount = 0;

export async function renderDag(dag, jobs) {
  const container = document.getElementById("dag-container");
  if (!container) {
    console.warn("dag-container not found");
    return;
  }

  if (!dag || !dag.nodes) {
    console.warn("Invalid dag data:", dag);
    return;
  }
  
  const syntax = generateMermaidSyntax(dag, jobs);
  
  // Mermaid requires unique IDs for re-rendering
  const graphId = `dag-${++renderCount}`;
  
  try {
    // mermaid.render returns { svg: string } in v10+
    const { svg } = await window.mermaid.render(graphId, syntax);
    container.innerHTML = svg;
  } catch (e) {
    console.error("Mermaid render error:", e);
    // Fallback: show the syntax for debugging
    container.innerHTML = `<pre class="text-red-500 text-xs p-2 bg-red-50 rounded">${e.message}\n\nSyntax:\n${syntax}</pre>`;
  }
}
