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
      href: 'downloads/OpenVoiceFlow-0.3.5-arm64.dmg',
      title: 'Apple Silicon DMG',
      subtitle: 'Recommended for M1, M2, M3, M4, and newer Macs running macOS 12 or later.',
      badge: 'Apple Silicon',
    },
    x86_64: {
      href: 'downloads/OpenVoiceFlow-0.3.5-x86_64.dmg',
      title: 'Intel DMG',
      subtitle: 'Recommended for x86_64 Intel Macs running macOS 12 or later.',
      badge: 'Intel Mac',
    },
  };

  const OS_LABELS = {
    windows: 'Windows',
    linux: 'Linux',
    chromeos: 'ChromeOS',
    android: 'Android',
    ios: 'iOS',
    ipados: 'iPadOS',
  };

  function trackRecommendation(result) {
    if (typeof window.va !== 'function') return;
    window.va('event', {
      name: 'download_recommendation_detected',
      data: {
        os: result.os || 'unknown',
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

  function detectOS() {
    const ua = navigator.userAgent || '';
    const uaData = navigator.userAgentData;
    const platform = String((uaData && uaData.platform) || navigator.platform || '').toLowerCase();
    const isMacLike = platform.includes('mac') || /Macintosh|Mac OS X/i.test(ua);

    if (/android/i.test(ua) || platform.includes('android')) return 'android';
    if (/iphone|ipod/i.test(ua)) return 'ios';
    // iPad Safari masquerades as a Mac but reports multitouch.
    if (/ipad/i.test(ua) || (isMacLike && (navigator.maxTouchPoints || 0) > 1)) return 'ipados';
    if (/CrOS/.test(ua) || platform.includes('cros') || platform.includes('chrome os')) return 'chromeos';
    if (platform.includes('win') || /Windows/i.test(ua)) return 'windows';
    if (isMacLike) return 'macos';
    if (platform.includes('linux') || /Linux|X11/i.test(ua)) return 'linux';
    return 'unknown';
  }

  // Safari never exposes userAgentData, so on Macs fall back to the WebGL
  // renderer string: Apple Silicon reports "Apple M1/M2/..." GPUs, Intel
  // Macs report Intel/AMD GPUs. Masked strings ("Apple GPU") stay unknown.
  function webglArchitectureHint() {
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
      if (!gl) return '';
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      const renderer = String(
        ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER) || ''
      );
      if (/Apple M\d/i.test(renderer)) return 'arm64';
      if (/(intel|amd|radeon|iris|nvidia)/i.test(renderer)) return 'x86_64';
      return '';
    } catch (error) {
      return '';
    }
  }

  async function detectPlatform() {
    const os = detectOS();
    if (os !== 'macos' && os !== 'unknown') {
      return { os, arch: '', confidence: 'high', source: 'not-mac' };
    }

    const uaData = navigator.userAgentData;
    if (uaData && typeof uaData.getHighEntropyValues === 'function') {
      try {
        const values = await uaData.getHighEntropyValues(['architecture', 'platform']);
        const hintedPlatform = String(values.platform || uaData.platform || '').toLowerCase();
        const hintedArch = normalizedArchitecture(values.architecture);
        if (hintedPlatform.includes('mac') && hintedArch) {
          return { os: 'macos', arch: hintedArch, confidence: 'high', source: 'userAgentData' };
        }
      } catch (error) {
        // Architecture hints are optional browser privacy surfaces.
      }
    }

    if (os === 'macos') {
      const webglArch = webglArchitectureHint();
      if (webglArch) {
        return { os: 'macos', arch: webglArch, confidence: 'medium', source: 'webgl' };
      }
      return { os: 'macos', arch: '', confidence: 'low', source: 'mac-undetected' };
    }

    return { os: 'unknown', arch: '', confidence: 'none', source: 'os-undetected' };
  }

  function setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function applyNotMacNotice(result) {
    const label = OS_LABELS[result.os] || 'this device';
    // Neutralize the CTA: an <a> without href is a non-interactive
    // placeholder, so a Windows/Linux visitor can't download a DMG that
    // will never run for them.
    cta.removeAttribute('href');
    cta.setAttribute('aria-disabled', 'true');
    cta.classList.remove('btn-primary');
    cta.classList.add('btn-unavailable');
    cta.textContent = `Not available for ${label}`;
    setText('downloadKicker', 'macOS required');
    setText('downloadTitle', 'OpenVoiceFlow is a Mac-only app');
    setText(
      'downloadSubtitle',
      `You appear to be browsing from ${label}. OpenVoiceFlow needs macOS 12 or newer — ` +
      `there is no ${label} version, and the Mac DMGs will not run on this device. ` +
      'Downloading for a Mac you own? Both builds stay available below.'
    );
    setText('downloadArchBadge', 'macOS 12+ only');
    setText('downloadConfidence', 'Detection runs locally in your browser; nothing is uploaded.');
  }

  function applyDownloadRecommendation(result) {
    document.querySelectorAll('[data-arch]').forEach(row => {
      row.classList.toggle('is-recommended', row.dataset.arch === result.arch);
    });

    if (result.source === 'not-mac') {
      applyNotMacNotice(result);
      trackRecommendation(result);
      return;
    }

    if (result.arch && builds[result.arch]) {
      const build = builds[result.arch];
      cta.href = build.href;
      cta.textContent = `Download ${build.title}`;
      setText('downloadKicker', 'Recommended for your Mac');
      setText('downloadTitle', build.title);
      setText('downloadSubtitle', build.subtitle);
      setText('downloadArchBadge', build.badge);
      setText(
        'downloadConfidence',
        result.source === 'webgl'
          ? 'Detected from this Mac’s GPU renderer string.'
          : 'Detected from browser architecture hints.'
      );
      trackRecommendation(result);
      return;
    }

    cta.href = builds.arm64.href;
    cta.textContent = 'Download Apple Silicon DMG';
    setText('downloadKicker', 'Choose your Mac build');
    setText('downloadTitle', 'Pick Apple Silicon or Intel');
    setText('downloadSubtitle', 'This browser did not expose enough detail to safely identify your chip. Apple menu →  About This Mac shows it: an "Apple M…" chip needs the Apple Silicon DMG, an Intel processor needs the Intel DMG.');
    setText('downloadArchBadge', 'macOS 12+');
    setText('downloadConfidence', 'Both Mac builds are listed below.');

    trackRecommendation(result);
  }

  detectPlatform().then(applyDownloadRecommendation);
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
