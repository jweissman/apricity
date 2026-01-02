// Dynamic DAG rendering with Mermaid
// Updates node colors based on job status

const STATUS_STYLES = {
  running: "fill:#fef3c7,stroke:#f59e0b,stroke-width:2.5px,rx:8,ry:8,min-width:200px",
  success: "fill:#ecfdf5,stroke:#10b981,stroke-width:2.5px,rx:8,ry:8,min-width:200px",
  failure: "fill:#fef2f2,stroke:#ef4444,stroke-width:2.5px,rx:8,ry:8,min-width:200px",
  skipped: "fill:#f8fafc,stroke:#94a3b8,stroke-width:2px,rx:8,ry:8,min-width:200px",
  pending: "fill:#fafafa,stroke:#e2e8f0,stroke-width:2px,rx:8,ry:8,min-width:200px,stroke-dasharray:5 5"
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
  
  // Add global class definitions for consistent styling
  lines.push("  classDef default font-size:14px,font-weight:500,padding:16px");
  
  // Add nodes with status-based styling and rounded rectangles
  dag.nodes.forEach((node) => {
    // Always compute safeId to ensure consistency
    const safe = safeId(node.id);
    // Use original ID for job status lookup
    const status = nodeStatus(node.id, jobs);
    const label = nodeLabel(node);
    
    // Use markdown string syntax for multi-line labels with better formatting
    // Escape any backticks in the label
    const escapedLabel = label.replace(/`/g, "'");
    
    // Add subtle status indicator emoji to label
    const statusEmoji = {
      running: "🔄 ",
      success: "✓ ",
      failure: "✗ ",
      skipped: "⊘ ",
      pending: ""
    }[status] || "";
    
    const labelWithStatus = statusEmoji ? `${statusEmoji}${escapedLabel}` : escapedLabel;
    
    // Use rounded rectangles for a softer look
    lines.push(`  ${safe}("\`${labelWithStatus}\`")`);
    lines.push(`  style ${safe} ${STATUS_STYLES[status]}`);
    // Add click handler to navigate to job (encode the ID for URL)
    lines.push(`  click ${safe} "#${encodeURIComponent(node.id)}"`);
  });
  
  // Add edges with smoother arrow style
  dag.edges.forEach(edge => {
    lines.push(`  ${safeId(edge.from)} -.-> ${safeId(edge.to)}`);
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
