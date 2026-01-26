# Rendering Architecture Analysis & Issues

## Critical Issues Identified

### 🚨 Issue #1: Initial Render vs Differential Render Use Different Code Paths

**The Problem:**
- **Initial render** uses `renderJob()` which creates HTML with `renderAnsi()` (fresh AnsiUp instance)
- **Differential render** uses `updateDifferential()` which only updates status icons
- **Terminal output updates** happen in `updateTerminalOutput()` which uses cached AnsiUp instances

This creates **THREE different rendering paths** that can produce inconsistent results!

**Example Inconsistency:**
```javascript
// Initial render (renderJob) - line 671
statusIconHtml = '<i class="fas fa-check text-emerald-600 text-xs"></i>';

// Differential update (updateDifferential) - line 438  
statusSpan.innerHTML = '<i class="fas fa-check text-emerald-600 text-xs"></i>';

// ✅ These match now, but ONLY because we just fixed them!
// Before, one used emerald-600, the other used success-600
```

**Root Cause:** String template duplication with no shared source of truth.

---

### 🚨 Issue #2: Terminal Output May Not Appear on First Render

**The Problem:**
When a job starts with output already available (e.g., from a previous run replay or fast-executing step):

1. **Initial render** at ~line 285 does this:
   ```javascript
   stepOutputLengths.clear();  // ❌ CLEARS ALL TRACKING
   ```

2. Then renders the job with full output
3. Then at line 322:
   ```javascript
   stepOutputLengths.set(`stdout-${stepId}`, (step.output.stdout || '').length);
   ```

4. **BUT** `updateTerminalOutput()` runs on a 150ms timer and checks:
   ```javascript
   const lastLen = stepOutputLengths.get(`stdout-${stepId}`) || 0;
   if (fullStdout.length > lastLen) { // Will be FALSE!
   ```

**Race Condition:**
- If `updateTerminalOutput()` runs BEFORE initial render completes → no output
- If toggle happens before tracking is set → output doesn't appear until refresh

**Evidence in code:**
```javascript
// render_job_list.js line 656 - initial render embeds the output
<pre id="stdout-${stepId}" class="stdout">${renderAnsi(step.output.stdout)}</pre>

// But then updateTerminalOutput tries to APPEND more
stdoutEl.insertAdjacentHTML('beforeend', newHtml);  // ❌ Will double-append!
```

---

### 🚨 Issue #3: Step Toggle Causes Full Re-render (Expensive!)

```javascript
window.toggleStepOutput = function (stepId) {
  run.ui.openSteps.add(stepId);
  
  lastRenderedSnapshot = null;  // ❌ Forces full rebuild
  renderJobList(run);           // ❌ Recreates ALL DOM
};
```

**Impact:**
- Every toggle destroys and recreates the entire job list
- Loses terminal scroll position
- Resets AnsiUp instances (loses ANSI state)
- Causes visual flicker

---

### 🚨 Issue #4: Duration Update Has Inconsistent Selectors

**In updateDifferential:**
```javascript
const durationSpan = stepEl.querySelector('.step-duration');
```

**In the timer (index.js line 118):**
```javascript
document.querySelectorAll('[data-started-at]').forEach(el => {
```

**In renderJob (line 643):**
```javascript
<span class="step-duration text-xs..." data-step-duration="${stepId}" 
      ${isRunning && step.startTime ? `data-started-at="${step.startTime}"` : ''}>
```

**Problem:** Using both `data-step-duration` and `data-started-at` - which one is canonical?

---

## Recommended Architecture Refactor

### Phase 1: Unify Rendering (High Priority)

Create a single source of truth for rendering each component:

```javascript
// render_components.js

/**
 * Single source of truth for status icon HTML
 */
export function renderStatusIcon(status, options = {}) {
  const { size = 'base', animate = true } = options;
  
  const configs = {
    running: {
      icon: 'fa-circle-notch',
      classes: 'text-warning-600',
      spin: true
    },
    success: {
      icon: 'fa-check',
      classes: 'text-success-600',
      size: 'xs'
    },
    failure: {
      icon: 'fa-times',
      classes: 'text-danger-600',
      size: 'xs'
    },
    pending: {
      icon: 'fa-circle',
      classes: 'text-frost-400',
      regular: true,
      size: 'xs'
    }
  };
  
  const config = configs[status] || configs.pending;
  const iconClass = config.regular ? 'far' : 'fas';
  const spin = config.spin && animate ? ' fa-spin' : '';
  const iconSize = config.size || size;
  
  return `<i class="${iconClass} ${config.icon}${spin} ${config.classes} text-${iconSize}"></i>`;
}

/**
 * Render step status background color classes
 */
export function getStepStatusClasses(status) {
  return {
    running: 'bg-white',
    success: 'bg-success-100',
    failure: 'bg-danger-100',
    pending: 'bg-frost-100',
    skipped: 'bg-frost-50'
  }[status] || 'bg-frost-100';
}

/**
 * Render step card classes (for differential updates AND initial render)
 */
export function getStepCardClasses(step) {
  const isPending = step.status === 'pending';
  const isRunning = step.status === 'running';
  
  return [
    'group rounded-md border transition-all',
    isPending ? 'border-frost-200 opacity-50' : '',
    isRunning ? 'border-warning-200 bg-warning-50/30' : '',
    !isPending && !isRunning ? 'border-frost-200 hover:border-frost-300 bg-white' : ''
  ].filter(Boolean).join(' ');
}
```

Then use these EVERYWHERE:

```javascript
// In renderJob:
statusIconHtml = renderStatusIcon(step.status);

// In updateDifferential:
statusSpan.innerHTML = renderStatusIcon(step.status);
```

---

### Phase 2: Fix Terminal Output Race Condition

**Strategy:** Make `updateTerminalOutput()` aware of whether it's seeing output for the first time.

```javascript
export function updateTerminalOutput(run) {
  const selectedJobId = getSelectedJobId();
  const activeJobId = selectedJobId || Object.keys(run.jobs)[0];
  const job = run.jobs[activeJobId];
  if (!job) return;

  for (const [stepName, step] of Object.entries(job.steps)) {
    if (!step.output) continue;
    
    const stepId = safeStepId(activeJobId, stepName);
    
    // Check if output container exists
    const stdoutEl = document.getElementById(`stdout-${stepId}`);
    if (!stdoutEl) continue; // Step not rendered yet or collapsed
    
    // Get current length from tracking OR from actual DOM content
    const currentTrackedLength = stepOutputLengths.get(`stdout-${stepId}`);
    
    // ✅ FIX: If we have content but no tracking, we're out of sync
    if (currentTrackedLength === undefined && step.output.stdout) {
      // This must be a fresh render - initialize tracking to current state
      stepOutputLengths.set(`stdout-${stepId}`, step.output.stdout.length);
      // Don't append anything - the initial render already put it there
      continue;
    }
    
    const fullStdout = step.output.stdout || '';
    const lastLen = currentTrackedLength || 0;
    
    if (fullStdout.length > lastLen) {
      const newChunk = fullStdout.slice(lastLen);
      const ansi = getAnsiInstance(`stdout-${stepId}`);
      const newHtml = ansi.ansi_to_html(newChunk);
      
      stdoutEl.insertAdjacentHTML('beforeend', newHtml);
      stepOutputLengths.set(`stdout-${stepId}`, fullStdout.length);
    }
  }
}
```

---

### Phase 3: Make Toggle Surgical (No Full Re-render)

```javascript
window.toggleStepOutput = function(stepId) {
  const outputEl = document.getElementById(`step-${stepId}-output`);
  if (!outputEl) return;
  
  const button = outputEl.previousElementSibling; // The header button
  const chevron = button?.querySelector('.fa-chevron-down');
  
  if (run.ui.openSteps.has(stepId)) {
    run.ui.openSteps.delete(stepId);
    outputEl.classList.add('hidden');
    if (chevron) chevron.classList.remove('rotate-180');
    if (button) button.setAttribute('aria-expanded', 'false');
  } else {
    run.ui.openSteps.add(stepId);
    outputEl.classList.remove('hidden');
    if (chevron) chevron.classList.add('rotate-180');
    if (button) button.setAttribute('aria-expanded', 'true');
    
    // ✅ Initialize output tracking when expanding for first time
    const job = run.jobs[Object.keys(run.jobs).find(id => stepId.includes(id))];
    const stepName = stepId.split('-').slice(2).join('-'); // Extract from stepId
    const step = job?.steps[stepName];
    
    if (step?.output) {
      if (!stepOutputLengths.has(`stdout-${stepId}`)) {
        stepOutputLengths.set(`stdout-${stepId}`, (step.output.stdout || '').length);
        stepOutputLengths.set(`stderr-${stepId}`, (step.output.stderr || '').length);
      }
    }
  }
  
  // ❌ NO MORE FULL RE-RENDER!
};
```

---

### Phase 4: Consolidate Duration Rendering

**Single attribute convention:**
```javascript
// ALWAYS use data-started-at for running steps
<span class="step-duration ..." 
      ${isRunning && step.startTime ? `data-started-at="${step.startTime}"` : ''}>

// Timer only looks for [data-started-at]
document.querySelectorAll('[data-started-at]').forEach(el => {
  const startedAtMs = Number(el.dataset.startedAt);
  // ... update
});

// Differential update uses same selector
const durationSpan = stepEl.querySelector('[data-started-at], .step-duration');
```

---

## Implementation Plan

### Quick Wins (Do First)
1. ✅ Extract status icon rendering to shared function
2. ✅ Fix terminal output race condition with sync detection
3. ✅ Make toggle surgical (no full re-render)
4. ✅ Consolidate duration selectors

### Medium-term Refactors
5. Extract all component rendering to render_components.js
6. Add render tests to catch divergence
7. Consider lightweight virtual DOM (or just better diffing)

### Long-term (Nice to Have)
8. Migrate to Preact/Solid.js (keeps bundle small, gets real reactivity)
9. Add proper state management (Zustand is tiny!)
10. Server-side render initial state for instant load

---

## Testing Strategy

Add visual regression tests:

```javascript
// test_rendering.js
import { renderStatusIcon, getStepCardClasses } from './render_components.js';

describe('Status Icon Rendering', () => {
  it('renders consistently for all statuses', () => {
    const statuses = ['running', 'success', 'failure', 'pending'];
    
    statuses.forEach(status => {
      const icon1 = renderStatusIcon(status);
      const icon2 = renderStatusIcon(status);
      
      expect(icon1).toBe(icon2); // Must be identical
      expect(icon1).toMatchSnapshot(); // Catch changes
    });
  });
});
```

---

## Summary

The core issue is **rendering path divergence**:
- Initial render uses one code path (string templates in renderJob)
- Differential updates use another (DOM manipulation in updateDifferential)
- Terminal output uses a third (incremental appends)

**Solution:** Extract all rendering logic to pure functions that return HTML strings or class lists. Use the SAME functions everywhere. This eliminates the possibility of divergence.

**Impact:**
- ✅ Consistent visuals between initial/refresh
- ✅ No more missing terminal output
- ✅ Faster toggles (no full rebuild)
- ✅ Easier to maintain (single source of truth)
- ✅ Easier to test (pure functions)
