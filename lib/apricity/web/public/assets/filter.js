// Filter runs by status
(function() {
  const filterSelect = document.getElementById('status-filter');
  if (!filterSelect) return;
  
  filterSelect.addEventListener('change', (e) => {
    const status = e.target.value;
    const runs = document.querySelectorAll('#job-list > div > a');
    
    runs.forEach(run => {
      if (status === 'all') {
        run.style.display = 'block';
      } else {
        const runStatus = run.querySelector('.text-amber-600, .text-green-600, .text-red-600');
        const statusText = runStatus?.textContent.toLowerCase() || '';
        
        const shouldShow = 
          (status === 'running' && statusText.includes('running')) ||
          (status === 'success' && statusText.includes('passed')) ||
          (status === 'failure' && statusText.includes('failed'));
        
        run.style.display = shouldShow ? 'block' : 'none';
      }
    });
  });
})();
