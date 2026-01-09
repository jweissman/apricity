// Keyboard shortcuts for Apricity UI
(function() {
  let helpVisible = false;
  
  // Create help overlay
  const helpDiv = document.createElement('div');
  helpDiv.className = 'keyboard-shortcuts';
  helpDiv.innerHTML = `
    <div class="mb-2 font-bold">Keyboard Shortcuts</div>
    <div class="space-y-1">
      <div><kbd>?</kbd> Toggle this help</div>
      <div><kbd>j</kbd> / <kbd>k</kbd> Next/Previous job</div>
      <div><kbd>e</kbd> Expand/collapse all steps</div>
      <div><kbd>r</kbd> Refresh page</div>
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
})();
