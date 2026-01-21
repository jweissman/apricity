// Keyboard shortcuts for Apricity UI
(function() {
  let helpVisible = false;
  
  // Create help overlay
  const helpDiv = document.createElement('div');
  helpDiv.className = 'keyboard-shortcuts';
  helpDiv.innerHTML = `
    <div class="mb-3 font-bold flex items-center">
      <span class="mr-2">⌨️</span> Keyboard Shortcuts
    </div>
    <div class="space-y-2 text-sm">
      <div class="flex justify-between gap-4"><span class="text-frost-400">Toggle help</span><kbd>?</kbd></div>
      <div class="flex justify-between gap-4"><span class="text-frost-400">Go to dashboard</span><kbd>h</kbd></div>
      <div class="flex justify-between gap-4"><span class="text-frost-400">Next / prev job</span><span><kbd>j</kbd> <kbd>k</kbd></span></div>
      <div class="flex justify-between gap-4"><span class="text-frost-400">Expand / collapse all</span><kbd>e</kbd></div>
      <div class="flex justify-between gap-4"><span class="text-frost-400">Refresh</span><kbd>r</kbd></div>
      <div class="flex justify-between gap-4"><span class="text-frost-400">Close dialogs</span><kbd>Esc</kbd></div>
    </div>
  `;
  document.body.appendChild(helpDiv);
  
  function toggleHelp() {
    helpVisible = !helpVisible;
    helpDiv.classList.toggle('visible', helpVisible);
  }
  
  // Sidebar toggle (for mobile)
  window.toggleSidebar = function() {
    const sidebar = document.getElementById('job-sidebar');
    if (sidebar) {
      sidebar.classList.toggle('collapsed');
    }
  };
  
  function navigateJobs(direction) {
    if (!window.location.hash) {
      // If no job selected, select the first one
      const firstLink = document.querySelector('.job-sidebar a');
      if (firstLink) firstLink.click();
      return;
    }
    
    const links = Array.from(document.querySelectorAll('.job-sidebar a'));
    const currentIndex = links.findIndex(link => 
      link.href.includes(window.location.hash)
    );
    
    if (currentIndex === -1) return;
    
    const nextIndex = direction === 'next' 
      ? Math.min(currentIndex + 1, links.length - 1)
      : Math.max(currentIndex - 1, 0);
    
    links[nextIndex]?.click();
  }
  
  function toggleAllSteps() {
    const buttons = document.querySelectorAll('.step-output');
    const allHidden = Array.from(buttons).every(el => el.classList.contains('hidden'));
    
    if (allHidden) {
      // Expand all
      buttons.forEach(el => {
        if (el.classList.contains('hidden')) {
          el.previousElementSibling?.click();
        }
      });
    } else {
      // Collapse all
      buttons.forEach(el => {
        if (!el.classList.contains('hidden')) {
          el.previousElementSibling?.click();
        }
      });
    }
  }
  
  document.addEventListener('keydown', (e) => {
    // Don't trigger if user is typing in an input
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
      return;
    }
    
    switch(e.key) {
      case '?':
        toggleHelp();
        e.preventDefault();
        break;
      case 'Escape':
        if (helpVisible) {
          toggleHelp();
          e.preventDefault();
        }
        break;
      case 'h':
        window.location.href = '/';
        e.preventDefault();
        break;
      case 'j':
        navigateJobs('next');
        e.preventDefault();
        break;
      case 'k':
        navigateJobs('prev');
        e.preventDefault();
        break;
      case 'e':
        toggleAllSteps();
        e.preventDefault();
        break;
      case 'r':
        location.reload();
        e.preventDefault();
        break;
    }
  });
  
  // Handle run button loading state
  document.querySelectorAll('.run-form').forEach(form => {
    form.addEventListener('submit', function(e) {
      const button = this.querySelector('.run-button');
      if (button) {
        button.disabled = true;
        button.classList.add('opacity-75', 'cursor-wait');
        button.innerHTML = '<i class="fas fa-circle-notch fa-spin text-xs"></i>';
      }
    });
  });
})();
