(() => {
  const hamburger = document.getElementById('navHamburger');
  const drawer = document.getElementById('navDrawer');
  if (!hamburger || !drawer || hamburger.dataset.navWired === 'true') return;

  hamburger.dataset.navWired = 'true';

  function setOpen(open) {
    hamburger.classList.toggle('active', open);
    drawer.classList.toggle('open', open);
    hamburger.setAttribute('aria-expanded', open ? 'true' : 'false');
  }

  hamburger.addEventListener('click', () => {
    setOpen(!drawer.classList.contains('open'));
  });

  drawer.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => setOpen(false));
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') setOpen(false);
  });
})();

(() => {
  function track(name, data = {}) {
    if (typeof window.va !== 'function') return;
    window.va('event', { name, data });
  }

  function pathname() {
    return window.location.pathname || '/';
  }

  document.querySelectorAll('a[href]').forEach(link => {
    const href = link.getAttribute('href') || '';
    if (!href.includes('/downloads/') && !href.startsWith('downloads/')) return;

    link.addEventListener('click', () => {
      const filename = href.split('/').pop() || href;
      const arch = filename.includes('arm64') ? 'arm64' : filename.includes('x86_64') ? 'x86_64' : 'unknown';
      const versionMatch = filename.match(/OpenVoiceFlow-([0-9]+\.[0-9]+\.[0-9]+)/);
      track('download_click', {
        arch,
        version: versionMatch ? versionMatch[1] : 'unknown',
        filename,
        source_path: pathname(),
      });
    });
  });

  document.querySelectorAll('a[href="install.html"], a[href="/install.html"]').forEach(link => {
    link.addEventListener('click', () => {
      track('install_guide_click', { source_path: pathname() });
    });
  });
})();
