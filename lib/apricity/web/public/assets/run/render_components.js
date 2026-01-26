/**
 * Shared rendering components for consistent UI across initial and differential renders.
 * 
 * This module provides single sources of truth for rendering status icons, badges,
 * and other UI components to prevent divergence between render paths.
 */

/**
 * Render status icon HTML - SINGLE SOURCE OF TRUTH
 * Used by both initial render and differential updates
 */
export function renderStatusIcon(status, options = {}) {
  const { size = 'base', animate = true } = options;
  
  const configs = {
    running: {
      icon: 'fa-circle-notch',
      classes: 'text-warning-600',
      spin: true,
      regular: false,
      label: 'Running'
    },
    success: {
      icon: 'fa-check',
      classes: 'text-success-600',
      size: 'xs',
      regular: false,
      label: 'Success'
    },
    failure: {
      icon: 'fa-times',
      classes: 'text-danger-500',
      size: 'xs',
      regular: false,
      label: 'Failed'
    },
    pending: {
      icon: 'fa-circle',
      classes: 'text-frost-400',
      size: 'xs',
      regular: true,  // far instead of fas
      label: 'Pending'
    },
    skipped: {
      icon: 'fa-forward',
      classes: 'text-frost-400',
      size: 'xs',
      regular: false,
      label: 'Skipped'
    }
  };
  
  const config = configs[status] || configs.pending;
  const iconClass = config.regular ? 'far' : 'fas';
  const spin = config.spin && animate ? ' fa-spin' : '';
  const iconSize = config.size || size;
  
  return `<i class="${iconClass} ${config.icon}${spin} ${config.classes} text-${iconSize}" aria-label="${config.label}" role="img"></i>`;
}

/**
 * Get step status icon background classes - SINGLE SOURCE OF TRUTH
 */
export function getStepIconBgClasses(status) {
  const classes = {
    running: 'bg-white',
    success: 'bg-success-100',
    failure: 'bg-danger-100',
    pending: 'bg-frost-100',
    skipped: 'bg-frost-50'
  };
  
  return classes[status] || 'bg-frost-100';
}

/**
 * Get step card border/background classes - SINGLE SOURCE OF TRUTH
 */
export function getStepCardClasses(status) {
  const baseClasses = 'group rounded-md border transition-all duration-200';
  
  switch (status) {
    case 'pending':
      return `${baseClasses} border-frost-200 opacity-50`;
    case 'running':
      return `${baseClasses} border-warning-200 bg-warning-50/30 hover:shadow-md hover:-translate-y-0.5`;
    case 'failure':
      return `${baseClasses} border-danger-200 bg-danger-50/20 hover:border-danger-300 hover:shadow-md hover:-translate-y-0.5`;
    case 'success':
      return `${baseClasses} border-success-200/50 bg-white hover:border-success-300 hover:shadow-sm hover:-translate-y-0.5`;
    default:
      return `${baseClasses} border-frost-200 hover:border-frost-300 bg-white hover:shadow-sm hover:-translate-y-0.5`;
  }
}

/**
 * Get step header classes - SINGLE SOURCE OF TRUTH
 */
export function getStepHeaderClasses(status, hasOutput) {
  const isPending = status === 'pending';
  const baseClasses = 'step-header w-full flex items-center justify-between px-5 py-3.5 text-left transition-colors rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sun-500 focus-visible:ring-offset-2';
  
  if (isPending) {
    return `${baseClasses} bg-frost-50 cursor-default`;
  } else if (hasOutput) {
    return `${baseClasses} hover:bg-frost-50/50 cursor-pointer active:bg-frost-100/50`;
  } else {
    return `${baseClasses} cursor-default`;
  }
}

/**
 * Get step name text classes - SINGLE SOURCE OF TRUTH
 */
export function getStepNameClasses(status) {
  const isPending = status === 'pending';
  // Use frost-600 for better contrast (WCAG AA compliant: 5.5:1 vs 3.2:1 for frost-400)
  return `step-name text-sm font-medium ${isPending ? 'text-frost-500' : 'text-frost-800'} truncate`;
}

/**
 * Render status badge - SINGLE SOURCE OF TRUTH
 */
export function renderStatusBadge(status) {
  const configs = {
    running: {
      bg: "bg-white",
      text: "text-warning-700",
      ring: "ring-1 ring-warning-100",
      dot: '<span class="w-1.5 h-1.5 rounded-full bg-warning-500 animate-pulse"></span>',
      label: "Running"
    },
    success: {
      bg: "bg-success-50",
      text: "text-success-700",
      ring: "ring-1 ring-success-100/80",
      dot: '<span class="w-1.5 h-1.5 rounded-full bg-success-500"></span>',
      label: "Passed"
    },
    failure: {
      bg: "bg-danger-50",
      text: "text-danger-700",
      ring: "ring-1 ring-danger-100/80",
      dot: '<span class="w-1.5 h-1.5 rounded-full bg-danger-500"></span>',
      label: "Failed"
    },
    pending: {
      bg: "bg-frost-50",
      text: "text-frost-600",
      ring: "ring-1 ring-frost-200/50",
      dot: '<span class="w-1.5 h-1.5 rounded-full bg-frost-300"></span>',
      label: "Pending"
    }
  };

  const config = configs[status] || configs.pending;
  return `<span class="inline-flex items-center gap-2 text-xs px-3 py-1.5 rounded-full font-medium ${config.bg} ${config.text} ${config.ring}">${config.dot}<span>${config.label}</span></span>`;
}

/**
 * Render sidebar status icon - SINGLE SOURCE OF TRUTH
 */
export function renderSidebarStatusIcon(status) {
  const icons = {
    running: "●",
    success: "●",
    failure: "●",
    pending: "○",
    skipped: "○"
  };
  
  return icons[status] || "○";
}

/**
 * Get sidebar status icon color - SINGLE SOURCE OF TRUTH
 */
export function getSidebarStatusIconColor(status) {
  const colors = {
    running: "text-warning-600",
    success: "text-success-600",
    failure: "text-danger-600",
    pending: "text-frost-300",
    skipped: "text-frost-400"
  };
  
  return colors[status] || "text-frost-300";
}
