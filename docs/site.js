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
      href: 'downloads/OpenVoiceFlow-0.4.1.dmg',
      title: 'Universal macOS DMG',
      subtitle: 'One universal native build for Apple Silicon and Intel Macs running macOS 14 or later.',
      badge: 'Universal macOS',
    },
    x86_64: {
      href: 'downloads/OpenVoiceFlow-0.4.1.dmg',
      title: 'Universal macOS DMG',
      subtitle: 'One universal native build for Apple Silicon and Intel Macs running macOS 14 or later.',
      badge: 'Universal macOS',
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

/* ── Waveform identity ──────────────────────────────────────────────────
   One brand waveform everywhere: the ring glyph (nav/footer), the hero
   listen→transcribe→type demo, the "02 · SPEAK" card wave, and the
   privacy-panel pipeline wave. Ported from the design spec; vanilla JS,
   no dependencies. Honors prefers-reduced-motion (static frames, full
   sentence shown immediately) and pauses when the tab is hidden. */
(() => {
  const canvases = Array.from(document.querySelectorAll('canvas[data-wf]'));
  if (!canvases.length) return;

  const typedNode = document.getElementById('typedDemo');
  const chipNode = document.getElementById('heroChip');
  const statusNode = document.getElementById('heroStatus');
  const TYPED_TEXT = 'Ship the beta tonight — the release notes are already in the doc.';

  const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
  const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');

  function palette() {
    const dark = darkQuery.matches;
    return {
      acc: dark ? '#E8974E' : '#B4661F',
      dim: dark ? 'rgba(214,208,194,.5)' : 'rgba(58,52,40,.45)',
      // The privacy panel is deliberately dark in both themes.
      pline: '#E8974E',
    };
  }

  const state = { loop: 'listen', amp: 0, tgt: 0, sylT: 0, last: 0 };
  const hist = new Float32Array(150);
  const timers = [];
  let typeTimer = null;
  let raf = 0;

  function after(ms, fn) { timers.push(setTimeout(fn, ms)); }

  function setLoop(loop) {
    state.loop = loop;
    if (chipNode) chipNode.classList.toggle('idle', loop !== 'listen');
    if (statusNode) {
      statusNode.textContent =
        loop === 'listen' ? 'listening'
        : loop === 'spool' ? 'transcribing — on device'
        : 'pasted at the cursor';
    }
  }

  function cycle() {
    setLoop('listen');
    if (typedNode) typedNode.textContent = '';
    after(3000, () => {
      setLoop('spool');
      after(900, () => {
        setLoop('type');
        let i = 0;
        typeTimer = setInterval(() => {
          i += 2;
          if (typedNode) typedNode.textContent = TYPED_TEXT.slice(0, i);
          if (i >= TYPED_TEXT.length) {
            clearInterval(typeTimer);
            typeTimer = null;
            after(2600, cycle);
          }
        }, 20);
      });
    });
  }

  function speechEnvelope(t) {
    const gate = (Math.sin(t * 0.9) + Math.sin(t * 0.53 + 1.2)) > 0.9 ? 0.06 : 1;
    let v = (Math.sin(t * 2.3) + Math.sin(t * 3.85 + 1.4) + Math.sin(t * 5.9 + 0.4)) / 3;
    v = Math.max(0, v * 0.75 + 0.5);
    return Math.min(1, v * gate);
  }

  function windowFn(u) { return Math.pow(Math.max(0, Math.sin(Math.PI * u)), 0.85); }

  function drawRing(ctx, w, h, t, color) {
    const cx = w / 2, cy = h / 2, R = Math.min(w, h) * 0.34, gap = 0.62, off = -1.0;
    ctx.beginPath();
    for (let a = off + gap / 2; a <= off + 2 * Math.PI - gap / 2; a += 0.045) {
      const r = R * (1 + 0.10 * Math.sin(a * 5 - t * 0.7));
      const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r;
      a <= off + gap / 2 + 0.05 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.lineWidth = 2.2;
    ctx.lineCap = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  function drawWave(ctx, w, h, t, ampAt, color, glow) {
    ctx.beginPath();
    const mid = h / 2;
    for (let x = 0; x <= w; x += 2) {
      const u = x / w, a = ampAt(u);
      const y = mid
        + (a < 0.03 ? Math.sin(x * 0.045 - t * 1.7) * 1.15 : 0)
        + a * h * 0.30 * (
          Math.sin(x * 0.052 + t * 6.6) * 0.55 +
          Math.sin(x * 0.117 - t * 9.4) * 0.26 +
          Math.sin(x * 0.026 + t * 3.2) * 0.42
        ) * windowFn(u);
      x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.strokeStyle = color;
    if (glow) { ctx.shadowColor = color; ctx.shadowBlur = 7; }
    ctx.stroke();
    ctx.shadowBlur = 0;
  }

  function drawSpool(ctx, w, h, t, color) {
    const cx = w / 2, cy = h / 2, rot = t * 6.9;
    ctx.beginPath();
    for (let a = 0; a <= 4 * Math.PI; a += 0.12) {
      const r = (2.5 + a * 0.95) * Math.min(1, h * 0.028);
      const x = cx + Math.cos(a + rot) * r, y = cy + Math.sin(a + rot) * r * 0.92;
      a === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  function paint(now) {
    const t = now / 1000;
    const dt = Math.min(50, now - (state.last || now));
    state.last = now;
    const colors = palette();

    if (state.loop === 'listen') {
      if (now > state.sylT) {
        state.sylT = now + 90 + Math.random() * 190;
        const r = Math.random();
        state.tgt = r < 0.18 ? 0.04 : 0.25 + Math.random() * 0.7;
      }
    } else {
      state.tgt = 0;
    }
    state.amp += (state.tgt - state.amp) * (1 - Math.exp(-dt / 70));
    hist.copyWithin(0, 1);
    hist[hist.length - 1] = state.amp;

    const d = Math.min(2, window.devicePixelRatio || 1);
    for (const el of canvases) {
      const w = el.clientWidth, h = el.clientHeight;
      if (!w || !h) continue;
      if (el.width !== (w * d | 0) || el.height !== (h * d | 0)) {
        el.width = w * d | 0;
        el.height = h * d | 0;
      }
      const ctx = el.getContext('2d');
      ctx.setTransform(d, 0, 0, d, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const mode = el.dataset.wf;

      if (mode === 'glyph') {
        drawRing(ctx, w, h, t, colors.acc);
      } else if (mode === 'hero') {
        if (state.loop === 'listen') {
          const n = hist.length;
          const ampAt = u => hist[Math.min(n - 1, (u * (n - 1)) | 0)];
          drawWave(ctx, w, h, t, ampAt, state.amp > 0.06 ? colors.acc : colors.dim, state.amp > 0.12);
        } else if (state.loop === 'spool') {
          drawSpool(ctx, w, h, t, colors.acc);
        } else {
          const mid = h / 2, cx = w / 2;
          ctx.beginPath();
          ctx.moveTo(cx - 8, mid);
          ctx.lineTo(cx + 8, mid);
          ctx.lineWidth = 2.4;
          ctx.lineCap = 'round';
          ctx.strokeStyle = colors.acc;
          ctx.stroke();
        }
      } else if (mode === 'card') {
        drawWave(ctx, w, h, t, u => speechEnvelope(t - (1 - u) * 1.25), colors.acc, true);
      } else if (mode === 'pline') {
        drawWave(ctx, w, h, t, u => speechEnvelope(t * 0.8 - (1 - u) * 1.4), colors.pline, true);
      }
    }
  }

  function tick(now) {
    if (!document.hidden) paint(now);
    raf = requestAnimationFrame(tick);
  }

  function staticFrame() {
    // Reduce Motion: one calm, representative frame — no loops, no typing.
    if (typedNode) typedNode.textContent = TYPED_TEXT;
    setLoop('listen');
    for (let i = 0; i < hist.length; i++) {
      hist[i] = speechEnvelope(i / 18) * 0.6;
    }
    state.amp = 0.4;
    state.loop = 'listen';
    paint(1000);
    if (statusNode) statusNode.textContent = 'listening';
  }

  if (motionQuery.matches) {
    staticFrame();
    darkQuery.addEventListener('change', staticFrame);
    window.addEventListener('resize', staticFrame);
  } else {
    cycle();
    raf = requestAnimationFrame(tick);
    motionQuery.addEventListener('change', () => {
      if (motionQuery.matches) {
        cancelAnimationFrame(raf);
        timers.forEach(clearTimeout);
        if (typeTimer) clearInterval(typeTimer);
        staticFrame();
      }
    });
  }
})();

/* ── Checksum copy buttons (download page) ─────────────────────────── */
(() => {
  document.querySelectorAll('.copy-btn[data-copy]').forEach(button => {
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
        const original = button.textContent;
        button.textContent = 'copied';
        setTimeout(() => { button.textContent = original; }, 1600);
      } catch (error) {
        // Clipboard API unavailable (http, older browser) — leave the
        // checksum selectable in the adjacent code block.
      }
    });
  });
})();
