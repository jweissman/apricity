// Filter runs by status
(function() {
  const filterSelect = document.getElementById('status-filter');
  if (!filterSelect) return;
  
  filterSelect.addEventListener('change', (e) => {
    const status = e.target.value;
    const runs = document.querySelectorAll('#job-list [data-status]');
    
    runs.forEach(run => {
      const runStatus = run.dataset.status;
      const shouldShow = status === 'all' || runStatus === status;
      run.style.display = shouldShow ? 'block' : 'none';
    });
  });
})();
