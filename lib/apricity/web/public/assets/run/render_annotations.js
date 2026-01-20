import humanize from "./util/humanize.js";
export function renderAnnotations(annotations) {
  // console.log("Rendering annotations:", annotations);
  if (!annotations || Object.keys(annotations).length === 0) {
    return `<div class="text-slate-400">No annotations available.</div>`;
  }
  const annotationElements = (elements) => Object.entries(elements)
    .filter(([k]) => k !== "_icon")
    .map(([k, v]) => `<span>${k}: <strong class="text-slate-700">${v}</strong></span>`)
    .join("")
  const annotationEntries = Object.entries(annotations)
    .map(([key, elements]) => `
                <div class="flex items-center justify-between p-3.5 bg-white/90 rounded-xl border border-indigo-200/60 hover:border-indigo-300 hover:shadow-sm transition-all duration-150">
                  <div class="flex items-center space-x-3 min-w-0">
                    <span class="text-lg flex-shrink-0">${elements._icon || '📋'}</span>
                    <div class="min-w-0">
                      <div class="text-sm font-semibold text-slate-800">${humanize(key)}</div>
                      <div class="text-xs text-slate-500 space-x-3">
                        ${annotationElements(elements)}
                      </div>
                    </div>
                  </div>
                </div>
              `).join("")
  return `
        <div class="mt-4 p-4 rounded-lg bg-indigo-50 border border-indigo-100">
          <h4 class="text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-3 flex items-center">
            <i class="fas fa-tags mr-2"></i>Annotations
          </h4>
          <div class="space-y-2">
            ${annotationEntries}
          </div>
        </div>
      `;
}