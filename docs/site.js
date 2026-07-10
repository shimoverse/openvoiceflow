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
  const panel = document.querySelector('[data-download-recommendation]');
  const cta = document.querySelector('[data-recommended-download]');
  if (!panel || !cta) return;

  const builds = {
    arm64: {
      href: 'downloads/OpenVoiceFlow-0.3.1-arm64.dmg',
      title: 'Apple Silicon DMG',
      subtitle: 'Recommended for M1, M2, M3, M4, and newer Macs running macOS 12 or later.',
      badge: 'Apple Silicon',
      confidence: 'Detected from browser architecture hints.',
    },
    x86_64: {
      href: 'downloads/OpenVoiceFlow-0.3.1-x86_64.dmg',
      title: 'Intel DMG',
      subtitle: 'Recommended for x86_64 Intel Macs running macOS 12 or later.',
      badge: 'Intel Mac',
      confidence: 'Detected from browser architecture hints.',
    },
  };

  function trackRecommendation(result) {
    if (typeof window.va !== 'function') return;
    window.va('event', {
      name: 'download_recommendation_detected',
      data: {
        arch: result.arch || 'unknown',
        confidence: result.confidence || 'unknown',
        source: result.source || 'unknown',
        source_path: window.location.pathname || '/',
      },
    });
  }

  function normalizedArchitecture(value) {
    const arch = String(value || '').toLowerCase();
    if (['arm', 'arm64', 'aarch64'].includes(arch)) return 'arm64';
    if (['x86', 'x86_64', 'x64', 'amd64', 'ia32'].includes(arch)) return 'x86_64';
    return '';
  }

  async function detectMacArchitecture() {
    const ua = navigator.userAgent || '';
    const platform = navigator.platform || '';
    const uaData = navigator.userAgentData;
    const isMac = /Mac/i.test(platform) || /Macintosh|Mac OS X/i.test(ua);

    if (uaData && typeof uaData.getHighEntropyValues === 'function') {
      try {
        const values = await uaData.getHighEntropyValues(['architecture', 'platform']);
        const hintedPlatform = String(values.platform || uaData.platform || '').toLowerCase();
        const hintedArch = normalizedArchitecture(values.architecture);
        if (hintedPlatform.includes('mac') && hintedArch) {
          return { arch: hintedArch, confidence: 'high', source: 'userAgentData' };
        }
      } catch (error) {
        // Architecture hints are optional browser privacy surfaces.
      }
    }

    if (!isMac) {
      return { arch: '', confidence: 'none', source: 'not-mac' };
    }

    return { arch: '', confidence: 'low', source: 'mac-undetected' };
  }

  function setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function applyDownloadRecommendation(result) {
    document.querySelectorAll('[data-arch]').forEach(row => {
      row.classList.toggle('is-recommended', row.dataset.arch === result.arch);
    });

    if (result.arch && builds[result.arch]) {
      const build = builds[result.arch];
      cta.href = build.href;
      cta.textContent = `Download ${build.title}`;
      setText('downloadKicker', 'Recommended for your Mac');
      setText('downloadTitle', build.title);
      setText('downloadSubtitle', build.subtitle);
      setText('downloadArchBadge', build.badge);
      setText('downloadConfidence', build.confidence);
      trackRecommendation(result);
      return;
    }

    cta.href = builds.arm64.href;
    cta.textContent = 'Download Apple Silicon DMG';

    if (result.source === 'not-mac') {
      setText('downloadKicker', 'Mac download only');
      setText('downloadTitle', 'Download OpenVoiceFlow for macOS');
      setText('downloadSubtitle', 'OpenVoiceFlow currently ships for macOS 12+ on Apple Silicon and Intel Macs.');
      setText('downloadArchBadge', 'macOS only');
      setText('downloadConfidence', 'Both Mac builds are listed below.');
    } else {
      setText('downloadKicker', 'Choose your Mac build');
      setText('downloadTitle', 'Pick Apple Silicon or Intel');
      setText('downloadSubtitle', 'This browser did not expose enough detail to safely identify your chip.');
      setText('downloadArchBadge', 'macOS 12+');
      setText('downloadConfidence', 'Both Mac builds are listed below.');
    }

    trackRecommendation(result);
  }

  detectMacArchitecture().then(applyDownloadRecommendation);
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
    const initialHref = link.getAttribute('href') || '';
    if (!initialHref.includes('/downloads/') && !initialHref.startsWith('downloads/')) return;

    link.addEventListener('click', () => {
      const href = link.getAttribute('href') || '';
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
