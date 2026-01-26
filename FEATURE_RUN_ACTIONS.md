# Feature Implementation Guide: Run Actions

This guide shows how to implement "Rerun" and "Rerun Failed" features with frontend-first implementation.

## Overview

Add action buttons to the run detail page that allow users to:
1. **Rerun** - Restart the entire pipeline with the same parameters
2. **Rerun Failed** - Only re-execute failed jobs
3. **Cancel** - Stop a running pipeline (if supported by backend)

## Frontend Implementation

### 1. Update Run Header (run.erb)

```erb
<!-- Run Header Card -->
<div class="bg-white rounded-xl border border-frost-200 shadow-sm p-6 mb-6">
  <div class="flex items-start justify-between">
    <div class="space-y-3 flex-1">
      <!-- Existing content ... -->
    </div>
    
    <!-- NEW: Action Buttons -->
    <div class="flex items-center gap-2 flex-shrink-0">
      <!-- Rerun Button -->
      <button 
        onclick="rerunPipeline('<%= @run.id %>', '<%= @pipeline.slug %>')"
        class="inline-flex items-center px-3 py-2 bg-white hover:bg-frost-50 
               text-frost-700 font-medium rounded-lg transition-colors 
               border border-frost-200 shadow-sm group"
        title="Rerun this pipeline">
        <i class="fas fa-redo mr-2 text-xs text-frost-400 group-hover:text-sun-600 
                  transition-colors"></i>
        Rerun
      </button>
      
      <!-- Rerun Failed Button (only show if there are failures) -->
      <% if @run.status == 'failure' %>
        <button 
          onclick="rerunFailed('<%= @run.id %>', '<%= @pipeline.slug %>')"
          class="inline-flex items-center px-3 py-2 bg-white hover:bg-warning-50 
                 text-frost-700 hover:text-warning-700 font-medium rounded-lg 
                 transition-colors border border-frost-200 hover:border-warning-200 
                 shadow-sm group"
          title="Rerun only failed jobs">
          <i class="fas fa-exclamation-triangle mr-2 text-xs text-frost-400 
                    group-hover:text-warning-600 transition-colors"></i>
          Rerun Failed
        </button>
      <% end %>
      
      <!-- Cancel Button (only show if running) -->
      <% if @run.status == 'running' %>
        <button 
          onclick="cancelRun('<%= @run.id %>')"
          class="inline-flex items-center px-3 py-2 bg-white hover:bg-danger-50 
                 text-frost-700 hover:text-danger-700 font-medium rounded-lg 
                 transition-colors border border-frost-200 hover:border-danger-200 
                 shadow-sm group"
          title="Cancel this run">
          <i class="fas fa-stop mr-2 text-xs text-frost-400 
                    group-hover:text-danger-600 transition-colors"></i>
          Cancel
        </button>
      <% end %>
    </div>
  </div>
</div>
```

### 2. Add JavaScript Handler (run/actions.js)

Create `/lib/apricity/web/public/assets/run/actions.js`:

```javascript
/**
 * Run actions: rerun, rerun failed, cancel
 */

/**
 * Rerun entire pipeline with same parameters
 */
export async function rerunPipeline(runId, pipelineSlug) {
  if (!confirm('Start a new run of this pipeline?')) {
    return;
  }
  
  try {
    showActionSpinner('rerun');
    
    const response = await fetch(`/pipelines/${pipelineSlug}/run`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        rerun_of: runId  // Optional: track that this is a rerun
      })
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    const data = await response.json();
    
    // Show success toast
    showToast('Pipeline started successfully!', 'success');
    
    // Redirect to new run after short delay
    setTimeout(() => {
      window.location.href = `/runs/${data.run_id}`;
    }, 1000);
    
  } catch (error) {
    console.error('Rerun failed:', error);
    showToast('Failed to start pipeline run', 'error');
    hideActionSpinner();
  }
}

/**
 * Rerun only failed jobs
 */
export async function rerunFailed(runId, pipelineSlug) {
  if (!confirm('Rerun only the failed jobs from this pipeline?')) {
    return;
  }
  
  try {
    showActionSpinner('rerun-failed');
    
    const response = await fetch(`/runs/${runId}/rerun-failed`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      }
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    const data = await response.json();
    
    showToast('Rerunning failed jobs...', 'success');
    
    setTimeout(() => {
      window.location.href = `/runs/${data.run_id}`;
    }, 1000);
    
  } catch (error) {
    console.error('Rerun failed:', error);
    showToast('Failed to rerun jobs', 'error');
    hideActionSpinner();
  }
}

/**
 * Cancel a running pipeline
 */
export async function cancelRun(runId) {
  if (!confirm('Cancel this pipeline run? Running jobs will be stopped.')) {
    return;
  }
  
  try {
    showActionSpinner('cancel');
    
    const response = await fetch(`/runs/${runId}/cancel`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      }
    });
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    showToast('Pipeline cancelled', 'success');
    
    // Reload page to show updated status
    setTimeout(() => {
      window.location.reload();
    }, 1000);
    
  } catch (error) {
    console.error('Cancel failed:', error);
    showToast('Failed to cancel pipeline', 'error');
    hideActionSpinner();
  }
}

/**
 * Show loading spinner on action button
 */
function showActionSpinner(action) {
  const button = event?.target?.closest('button');
  if (!button) return;
  
  button.disabled = true;
  button.classList.add('opacity-60', 'cursor-wait');
  
  const icon = button.querySelector('i');
  if (icon) {
    icon.className = 'fas fa-circle-notch fa-spin mr-2 text-xs';
  }
}

/**
 * Hide loading spinner
 */
function hideActionSpinner() {
  const button = event?.target?.closest('button');
  if (!button) return;
  
  button.disabled = false;
  button.classList.remove('opacity-60', 'cursor-wait');
}

/**
 * Show toast notification
 */
function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  
  const styles = {
    success: 'bg-success-50 text-success-700 ring-1 ring-success-100',
    error: 'bg-danger-50 text-danger-700 ring-1 ring-danger-100',
    info: 'bg-frost-100 text-frost-700 ring-1 ring-frost-200'
  };
  
  const icons = {
    success: 'fa-check-circle',
    error: 'fa-exclamation-circle',
    info: 'fa-info-circle'
  };
  
  toast.className = `fixed bottom-6 right-6 px-4 py-3 rounded-lg shadow-lg 
    ${styles[type]} animate-slide-in flex items-center gap-2 z-50`;
  
  toast.innerHTML = `
    <i class="fas ${icons[type]}"></i>
    <span class="font-medium">${message}</span>
  `;
  
  document.body.appendChild(toast);
  
  setTimeout(() => {
    toast.style.animation = 'slide-out 0.3s ease-out forwards';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

// Expose functions globally for inline onclick handlers
window.rerunPipeline = rerunPipeline;
window.rerunFailed = rerunFailed;
window.cancelRun = cancelRun;
```

### 3. Add CSS Animations (style.css)

```css
/* Toast animations */
@keyframes slide-in {
  from {
    opacity: 0;
    transform: translateX(100%);
  }
  to {
    opacity: 1;
    transform: translateX(0);
  }
}

@keyframes slide-out {
  from {
    opacity: 1;
    transform: translateX(0);
  }
  to {
    opacity: 0;
    transform: translateX(100%);
  }
}

.animate-slide-in {
  animation: slide-in 0.3s ease-out;
}
```

### 4. Update run.erb to Include Script

```erb
<!-- At bottom of run.erb, after existing scripts -->
<script src="/assets/run/index.js" type="module"></script>
<script src="/assets/run/actions.js" type="module"></script>
```

## Backend Implementation (Minimal Example)

### Ruby/Sinatra Route Handlers

```ruby
# In lib/apricity/web/april.rb

post "/runs/:id/rerun-failed" do
  run_id = params[:id]
  run = Apricity::RunStore.instance.get_run(run_id)
  halt 404, { error: "Run not found" }.to_json unless run
  
  # Get failed jobs from original run
  failed_jobs = run.jobs.select { |job| job.status == 'failure' }
  
  # Create new run with only failed jobs
  new_run = create_partial_run(run.pipeline_slug, failed_jobs)
  
  content_type :json
  { 
    run_id: new_run.id,
    message: "Rerunning #{failed_jobs.size} failed jobs"
  }.to_json
end

post "/runs/:id/cancel" do
  run_id = params[:id]
  run = Apricity::RunStore.instance.get_run(run_id)
  halt 404, { error: "Run not found" }.to_json unless run
  
  # Send cancellation signal to worker
  cancel_run(run_id)
  
  content_type :json
  { 
    message: "Run cancelled"
  }.to_json
end
```

## Alternative: Simpler Client-Side Only Approach

If you want to avoid backend changes initially, you can implement rerun as a simple form POST:

```erb
<!-- Rerun using existing /pipelines/:slug/run endpoint -->
<form action="/pipelines/<%= @pipeline.slug %>/run" method="post" class="inline">
  <input type="hidden" name="rerun_of" value="<%= @run.id %>">
  <button 
    type="submit"
    class="inline-flex items-center px-3 py-2 bg-white hover:bg-frost-50 
           text-frost-700 font-medium rounded-lg transition-colors 
           border border-frost-200 shadow-sm group">
    <i class="fas fa-redo mr-2 text-xs text-frost-400 group-hover:text-sun-600"></i>
    Rerun
  </button>
</form>
```

This reuses your existing pipeline run endpoint without needing new backend routes!

## Enhanced UX: Optimistic Updates

For even better UX, show the new run immediately before the backend confirms:

```javascript
export async function rerunPipeline(runId, pipelineSlug) {
  // Generate temporary ID for optimistic update
  const tempRunId = `temp-${Date.now()}`;
  
  // Show optimistic run in UI immediately
  addOptimisticRun(tempRunId, pipelineSlug);
  
  // Redirect to a "pending" view
  window.location.href = `/runs/${tempRunId}?pending=true`;
  
  // Actual request happens in background
  const response = await fetch(...);
  
  // Replace temp ID with real ID when available
  if (response.ok) {
    const data = await response.json();
    window.history.replaceState(null, '', `/runs/${data.run_id}`);
  }
}
```

## Testing Checklist

- [ ] Rerun button triggers new pipeline run
- [ ] New run appears in runs list immediately
- [ ] User is redirected to new run page
- [ ] Toast notifications show success/error states
- [ ] Button shows loading spinner during request
- [ ] Failed jobs list is correctly identified
- [ ] Rerun failed only executes failed jobs
- [ ] Cancel button only shows for running pipelines
- [ ] Confirmation dialogs prevent accidental clicks
- [ ] Error states are handled gracefully

## Future Enhancements

1. **Run Comparison**: After rerun, show diff between original and new run
2. **Schedule Rerun**: Delay rerun until certain time
3. **Rerun with Changes**: Allow user to modify parameters before rerun
4. **Bulk Rerun**: Rerun multiple failed runs at once from runs list
5. **Auto-rerun**: Automatically rerun on failure (with backoff)

## Visual Examples

### Action Buttons (Normal State)
```
┌────────────────────────────────────────────────┐
│  Run abc1234          [↻ Rerun] [⚠ Rerun Failed] [⏹ Cancel]  │
│  ● Running                                                     │
└────────────────────────────────────────────────┘
```

### Action Buttons (Loading State)
```
┌────────────────────────────────────────────────┐
│  Run abc1234          [⏳ Rerun]                              │
│  ● Running                                                     │
└────────────────────────────────────────────────┘
```

### Toast Notification
```
                                    ┌─────────────────────────┐
                                    │ ✓ Pipeline started!     │
                                    └─────────────────────────┘
```

---

This implementation provides a solid foundation for run actions with good UX patterns. Start with the simple form-based approach, then enhance with the JavaScript version for better feedback and validation.
