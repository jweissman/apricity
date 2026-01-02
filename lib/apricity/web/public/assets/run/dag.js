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
    .replace(/,/g, "_")
    .replace(/\s+/g, "_");
}

function titleCase(str) {
  return str
    .replace(/_/g, " ")
    .replace(/\b\w/g, c => c.toUpperCase());
}

/**
 * Generate a display label for a node.
 * For matrix jobs, shows the job name with matrix index (e.g., "Test Job 1/4")
 * and matrix variables on a second line.
 */
function nodeLabel(node) {
  const baseName = titleCase(node.label);
  
  // Not a matrix job - just return the name
  if (!node.matrixIndex) {
    return baseName;
  }
  
  // Matrix job - build multi-line label
  const indexLabel = `${node.matrixIndex}/${node.matrixTotal}`;
  const matrixVars = formatMatrixVars(node.matrix);
  
  if (matrixVars) {
    // Multi-line: "Job Name 1/4" + matrix vars on second line
    return `${baseName} ${indexLabel}\n${matrixVars}`;
  }
  
  return `${baseName} ${indexLabel}`;
}

/**
 * Format matrix variables for display.
 * e.g., { shard: 1, ruby: "3.4" } -> "shard=1, ruby=3.4"
 */
function formatMatrixVars(matrix) {
  if (!matrix || Object.keys(matrix).length === 0) {
    return null;
  }
  
  return Object.entries(matrix)
    .map(([key, value]) => `${key}=${value}`)
    .join(", ");
}

export function generateMermaidSyntax(dag, jobs) {
  const lines = ["graph LR"];
  
  // Add nodes with status-based styling and square shape
  dag.nodes.forEach((node) => {
    // Always compute safeId to ensure consistency
    const safe = safeId(node.id);
    // Use original ID for job status lookup
    const status = nodeStatus(node.id, jobs);
    const label = nodeLabel(node);
    
    // Use markdown string syntax for multi-line labels
    // Escape any backticks in the label
    const escapedLabel = label.replace(/`/g, "'");
    lines.push(`  ${safe}["\`${escapedLabel}\`"]`);
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
