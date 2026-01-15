// Dynamic DAG rendering with Mermaid
// Winter sun palette - cool, calm, professional

const STATUS_STYLES = {
  running: "fill:#fef3c7,stroke:#fbbf24,stroke-width:2px",
  success: "fill:#ecfdf5,stroke:#34d399,stroke-width:2px",
  failure: "fill:#fef2f2,stroke:#f87171,stroke-width:2px",
  skipped: "fill:#f8fafc,stroke:#cbd5e1,stroke-width:1.5px",
  pending: "fill:#f8fafc,stroke:#e2e8f0,stroke-width:1.5px,stroke-dasharray:4 4"
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
 * For matrix jobs, shows everything on one line for wide brick-like nodes.
 */
function nodeLabel(node) {
  const baseName = titleCase(node.label);
  
  // Not a matrix job - just return the name
  if (!node.matrixIndex) {
    return baseName;
  }
  
  // Matrix job - single line with compact matrix info
  const indexLabel = `${node.matrixIndex}/${node.matrixTotal}`;
  const matrixVars = formatMatrixVarsCompact(node.matrix);
  
  // Format: "Test Job #1/4 · shard=1"
  if (matrixVars) {
    return `${baseName} #${indexLabel} · ${matrixVars}`;
  }
  
  return `${baseName} #${indexLabel}`;
}

/**
 * Format matrix variables compactly for inline display.
 */
function formatMatrixVarsCompact(matrix) {
  if (!matrix || Object.keys(matrix).length === 0) {
    return null;
  }
  
  return Object.entries(matrix)
    .map(([key, value]) => `${key}=${value}`)
    .join(" ");
}

export function generateMermaidSyntax(dag, jobs) {
  const lines = ["graph LR"];  // Left to right for traditional pipeline flow
  
  // Add nodes with status-based styling
  dag.nodes.forEach((node) => {
    const safe = safeId(node.id);
    const status = nodeStatus(node.id, jobs);
    const label = nodeLabel(node);
    
    // Use stadium shape ([label]) for rounded wide nodes
    lines.push(`  ${safe}([${label}])`);
    lines.push(`  style ${safe} ${STATUS_STYLES[status]}`);
    lines.push(`  click ${safe} "#${encodeURIComponent(node.id)}"`);
  });
  
  // Add edges with solid arrows
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
  
  // Debug: log the generated syntax
  // console.log("Generated Mermaid syntax:", syntax);
  
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
