import humanize from "./util/humanize.js";
export function renderAnnotations(annotations) {
  // console.log("Rendering annotations:", annotations);
  if (!annotations || Object.keys(annotations).length === 0) {
    return `<div class="text-gray-400">No annotations available.</div>`;
  }
  const annotationElements = (elements) => Object.entries(elements)
    .filter(([k]) => k !== "_icon")
    .map(([k, v]) => `<span>${k}: <strong class="text-gray-800">${v}</strong></span>`)
    .join("")
  const annotationEntries = Object.entries(annotations)
    .map(([key, elements]) => `
                <div class="flex items-start space-x-2">
                  <span class="text-lg">${elements._icon || '📋'}</span>
                  <div>
                    <div class="font-medium text-gray-700 text-sm">${humanize(key)}</div>
                    <div class="text-xs text-gray-500 space-x-3">
                      ${annotationElements(elements)}
                    </div>
                  </div>
                </div>
              `).join("")
  return `
        <div class="mt-4 p-4 rounded-lg bg-indigo-50 border border-indigo-100">
          <h4 class="text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-3">Annotations</h4>
          <div class="space-y-2"></div>
            ${annotationEntries}
          </div>
        </div>
      `;
}