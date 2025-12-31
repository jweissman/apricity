function statusIcon(status) {
  return {
    running: "⏳",
    success: "✅",
    failure: "❌"
  }[status] || "❔";
}

function humanize(str) {
  return str
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function renderJobList(run) {
  const el = document.getElementById("job-list");
  el.innerHTML = "";

  const jobSidebar = document.createElement("div");
  jobSidebar.className = "job-sidebar";
  jobSidebar.classList.add("p-4", "border-r", "min-w-48", "h-full");
  jobSidebar.innerHTML = `
    <h2 class="text-xl font-bold mb-4">Jobs</h2>
    <ul class="mb-4">
      ${Object.entries(run.jobs)
      .map(
        ([nodeId, job]) =>
          `<li class="mb-2 border-b pb-1">
              <a href="#${nodeId}">
                ${statusIcon(job.status)} 
                ${nodeId}
              </a>
            </li>`
      )
      .join("")}
    </ul>
  `;

  const jobContent = document.createElement("div");

  for (const [nodeId, job] of Object.entries(run.jobs)) {
    // if we have a #href in the URL, only render that job
    const hash = window.location.hash.slice(1);
    if (hash && hash !== nodeId) continue;
    jobContent.appendChild(renderJob(job, nodeId));
  }

  const flexContainer = document.createElement("div");
  flexContainer.style.display = "flex";
  flexContainer.style.gap = "20px";

  flexContainer.appendChild(jobSidebar);
  flexContainer.appendChild(jobContent);

  el.appendChild(flexContainer);
}

window.toggleStepOutput = function (stepId) {
  if (run.ui.openSteps.has(stepId)) {
    run.ui.openSteps.delete(stepId);
  } else {
    run.ui.openSteps.add(stepId);
  }
  renderJobList(run);
};

function renderJob(job, nodeId) {
  const jobEl = document.createElement("div");
  jobEl.className = "job-card";

  jobEl.innerHTML = `
      <div>
      <h3 id="${nodeId}" class="text-lg font-bold mb-2">Job: ${nodeId} ${statusIcon(job.status)}</h3>
      <ul class="steps ml-4">
        ${Object.entries(job.steps)
      .map(([name, step]) => {
        const stepId = `step-${nodeId}-${name}`;
        const isOpen = run.ui.openSteps.has(stepId);

        return `<li>
            <div class="step-name font-bold cursor-pointer"
            onclick="toggleStepOutput('${stepId}')">
              ${statusIcon(step.status)} ${name}
            </div>
            <div id="step-${name}-output"
              class="step-output rounded border p-2 bg-black text-white mt-2 ${isOpen ? "" : "hidden"}">
              <pre class="stdout">${step.output.stdout}</pre>
              <pre class="stderr" style="color: red;">${step.output.stderr}</pre>
            </div>
           </li>`
        })
      .join("")}
      </ul>
      <ul class="annotations ml-4">
        ${job.annotations
      ? Object.entries(job.annotations)
        .map(
          ([key, elements]) =>
            `<li><strong>${elements._icon} ${humanize(key)}</strong> ${Object.entries(elements).map(
              ([k, v]) => (k === "_icon" ? "" : `<div class="ml-6">${k}: ${v}</div>`)
            ).join("")
            }</li>`
        )
        .join("")
      : ""}
      </ul>
      </div>
    `;
  return jobEl;
}
