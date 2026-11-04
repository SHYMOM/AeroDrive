/**
 * AeroDrive Website — Interactive JS
 * Covers: particle canvas, custom cursor, scroll progress, navbar reveal,
 * scroll-reveal (IntersectionObserver), tabs, FAQ accordion, download modal,
 * architecture stepper, calculator with animated bar chart, counter animations,
 * card tilt (3D perspective), magnetic button effect, ripple on click.
 */

'use strict';

/* ============================================================
   UTILITY HELPERS
   ============================================================ */

/** Clamp a number between min and max */
function clamp(val, min, max) {
  return Math.min(Math.max(val, min), max);
}

/** Linear interpolation */
function lerp(a, b, t) {
  return a + (b - a) * t;
}

/** Format large numbers with commas */
function formatNumber(n) {
  return Math.floor(n).toLocaleString('en-US');
}

/* ============================================================
   1. PARTICLE CANVAS — Animated star field
   ============================================================ */
(function initParticles() {
  const canvas = document.getElementById('particle-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  let w, h, particles;
  const COUNT = 110;
  const SPEED = 0.18;

  function resize() {
    w = canvas.width  = window.innerWidth;
    h = canvas.height = window.innerHeight;
  }

  function createParticles() {
    particles = Array.from({ length: COUNT }, () => ({
      x:      Math.random() * w,
      y:      Math.random() * h,
      r:      Math.random() * 1.4 + 0.3,
      dx:     (Math.random() - 0.5) * SPEED,
      dy:     (Math.random() - 0.5) * SPEED,
      alpha:  Math.random() * 0.5 + 0.15,
      // give a few particles a subtle indigo tint
      color:  Math.random() > 0.75 ? '99,102,241' : '241,245,249',
    }));
  }

  function drawFrame() {
    ctx.clearRect(0, 0, w, h);
    for (const p of particles) {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${p.color}, ${p.alpha})`;
      ctx.fill();

      p.x += p.dx;
      p.y += p.dy;

      // Wrap around edges
      if (p.x < 0)  p.x = w;
      if (p.x > w)  p.x = 0;
      if (p.y < 0)  p.y = h;
      if (p.y > h)  p.y = 0;
    }
    requestAnimationFrame(drawFrame);
  }

  resize();
  createParticles();
  drawFrame();

  window.addEventListener('resize', () => {
    resize();
    createParticles();
  });
})();

/* ============================================================
   2. CUSTOM CURSOR
   ============================================================ */
(function initCursor() {
  const dot  = document.getElementById('cursor-dot');
  const ring = document.getElementById('cursor-ring');
  if (!dot || !ring) return;

  // Only on non-touch devices
  if (window.matchMedia('(pointer: coarse)').matches) return;

  let mouseX = -100, mouseY = -100;
  let ringX  = -100, ringY  = -100;
  let isActive = false;

  document.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
    if (!isActive) {
      dot.style.opacity  = '1';
      ring.style.opacity = '1';
      isActive = true;
    }
  });

  document.addEventListener('mouseleave', () => {
    dot.style.opacity  = '0';
    ring.style.opacity = '0';
    isActive = false;
  });

  // Hover state on interactive elements
  const hoverEls = document.querySelectorAll('a, button, [data-tilt], input[type="range"]');
  hoverEls.forEach(el => {
    el.addEventListener('mouseenter', () => ring.classList.add('cursor-hover'));
    el.addEventListener('mouseleave', () => ring.classList.remove('cursor-hover'));
  });

  function animateCursor() {
    dot.style.left = mouseX + 'px';
    dot.style.top  = mouseY + 'px';

    ringX = lerp(ringX, mouseX, 0.14);
    ringY = lerp(ringY, mouseY, 0.14);
    ring.style.left = ringX + 'px';
    ring.style.top  = ringY + 'px';

    requestAnimationFrame(animateCursor);
  }
  animateCursor();
})();

/* ============================================================
   3. SCROLL PROGRESS BAR
   ============================================================ */
(function initScrollProgress() {
  const bar = document.getElementById('scroll-progress');
  if (!bar) return;

  function update() {
    const scrollTop = document.documentElement.scrollTop || document.body.scrollTop;
    const scrollHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
    const pct = scrollHeight > 0 ? (scrollTop / scrollHeight) * 100 : 0;
    bar.style.width = pct + '%';
  }

  window.addEventListener('scroll', update, { passive: true });
  update();
})();

/* ============================================================
   4. NAVBAR — Active section highlighting via IntersectionObserver
   ============================================================ */
(function initNavHighlight() {
  const navLinks = document.querySelectorAll('.nav-link[data-section]');
  if (!navLinks.length) return;

  const sections = document.querySelectorAll('section[id]');

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const id = entry.target.id;
        navLinks.forEach(link => {
          link.classList.toggle('active', link.getAttribute('data-section') === id);
        });
      }
    });
  }, { rootMargin: '-20% 0px -70% 0px', threshold: 0 });

  sections.forEach(s => observer.observe(s));
})();

/* ============================================================
   5. MOBILE HAMBURGER MENU
   ============================================================ */
(function initMobileMenu() {
  const hamburger = document.getElementById('hamburger');
  const mobileNav = document.getElementById('mobile-nav');
  const overlay   = document.getElementById('mobile-nav-overlay');
  if (!hamburger || !mobileNav || !overlay) return;

  function open() {
    hamburger.classList.add('open');
    mobileNav.classList.add('open');
    overlay.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function close() {
    hamburger.classList.remove('open');
    mobileNav.classList.remove('open');
    overlay.classList.remove('open');
    document.body.style.overflow = '';
  }

  hamburger.addEventListener('click', () => {
    if (hamburger.classList.contains('open')) close(); else open();
  });

  overlay.addEventListener('click', close);

  // Close on nav link click
  document.querySelectorAll('.mobile-nav-link').forEach(link => {
    link.addEventListener('click', close);
  });
})();

/* ============================================================
   6. SCROLL REVEAL — IntersectionObserver (sections & cards)
   ============================================================ */
(function initScrollReveal() {
  const els = document.querySelectorAll('.reveal-section');
  if (!els.length) return;

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('revealed');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08 });

  els.forEach(el => observer.observe(el));
})();

/* ============================================================
   7. FEATURE TABS — Smooth crossfade with pill highlight
   ============================================================ */
(function initTabs() {
  const tabButtons  = document.querySelectorAll('.tab-btn');
  const tabContents = document.querySelectorAll('.tab-content');
  if (!tabButtons.length) return;

  tabButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-tab');

      tabButtons.forEach(b  => b.classList.remove('active'));
      tabContents.forEach(c => c.classList.remove('active'));

      btn.classList.add('active');
      const targetContent = document.getElementById(targetId);
      if (targetContent) targetContent.classList.add('active');
    });
  });
})();

/* ============================================================
   8. ARCHITECTURE FLOW STEP CARDS — Click highlight
   ============================================================ */
(function initFlowSteps() {
  const flowCards = document.querySelectorAll('.flow-step-card');
  if (!flowCards.length) return;

  flowCards.forEach(card => {
    card.addEventListener('click', () => {
      flowCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
    });
    card.addEventListener('mouseenter', () => {
      flowCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
    });
  });
})();

/* ============================================================
   9. CALCULATOR — Slider + animated bar chart + savings
   ============================================================ */
(function initCalculator() {
  const slider        = document.getElementById('storage-slider');
  const storageDisplay = document.getElementById('storage-display');
  const gdriveCost    = document.getElementById('gdrive-cost');
  const dropboxCost   = document.getElementById('dropbox-cost');
  const icloudCost    = document.getElementById('icloud-cost');
  const gdriveBar     = document.getElementById('gdrive-bar');
  const dropboxBar    = document.getElementById('dropbox-bar');
  const icloudBar     = document.getElementById('icloud-bar');
  const savingsEl     = document.getElementById('calc-savings');

  if (!slider) return;

  // Max bar height in CSS pixels (we calculate relative percentages)
  const MAX_COST = 700; // cap for visual scaling

  function computeCosts(gb) {
    // Google One
    let gCost;
    if (gb <= 200)        gCost = 30;
    else if (gb <= 2000)  gCost = 100;
    else                  gCost = Math.round(100 + ((gb - 2000) / 1000) * 60);

    // Dropbox Plus
    let dCost;
    if (gb <= 2000) dCost = 120;
    else            dCost = Math.round(120 + ((gb - 2000) / 1000) * 72);

    // iCloud+
    let iCost;
    if (gb <= 200)        iCost = 36;
    else if (gb <= 2000)  iCost = 120;
    else                  iCost = Math.round(120 + ((gb - 2000) / 1000) * 65);

    return { gCost, dCost, iCost };
  }

  function setBarHeight(barEl, cost) {
    if (!barEl) return;
    const pct = clamp((cost / MAX_COST) * 100, 1, 100);
    barEl.style.height = pct + '%';
  }

  function updateCalculator() {
    const gb  = parseInt(slider.value, 10);
    const tb  = (gb / 1000).toFixed(1);

    // Storage label
    if (storageDisplay) {
      storageDisplay.textContent = gb >= 1000
        ? (parseFloat(tb) % 1 === 0 ? parseInt(tb) + ' TB' : tb + ' TB')
        : gb + ' GB';
    }

    const { gCost, dCost, iCost } = computeCosts(gb);

    // Update cost labels
    if (gdriveCost)  gdriveCost.textContent  = '$' + gCost;
    if (dropboxCost) dropboxCost.textContent = '$' + dCost;
    if (icloudCost)  icloudCost.textContent  = '$' + iCost;

    // Update bar heights
    setBarHeight(gdriveBar,  gCost);
    setBarHeight(dropboxBar, dCost);
    setBarHeight(icloudBar,  iCost);

    // Savings vs cheapest paid plan
    const cheapest = Math.min(gCost, dCost, iCost);
    if (savingsEl) savingsEl.textContent = '$' + cheapest;

    // Color the slider track fill
    const pct = ((gb - parseInt(slider.min)) / (parseInt(slider.max) - parseInt(slider.min))) * 100;
    slider.style.background = `linear-gradient(90deg, #6366f1 ${pct}%, rgba(255,255,255,0.08) ${pct}%)`;
  }

  slider.addEventListener('input', updateCalculator);
  updateCalculator(); // Initial render
})();

/* ============================================================
   10. ANIMATED COUNTERS — Number count-up on scroll-enter
   ============================================================ */
(function initCounters() {
  const statValues = document.querySelectorAll('.stat-value[data-count]');
  if (!statValues.length) return;

  function animateCounter(el) {
    const target  = parseInt(el.getAttribute('data-count'), 10);
    const prefix  = el.getAttribute('data-prefix')  || '';
    const suffix  = el.getAttribute('data-suffix')  || '';
    const duration = 1800; // ms
    const start   = performance.now();

    function tick(now) {
      const elapsed = now - start;
      const progress = clamp(elapsed / duration, 0, 1);
      // Ease out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(eased * target);
      el.textContent = prefix + (target >= 10000 ? formatNumber(current) : current) + suffix;

      if (progress < 1) requestAnimationFrame(tick);
      else el.textContent = prefix + (target >= 10000 ? formatNumber(target) : target) + suffix;
    }
    requestAnimationFrame(tick);
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        animateCounter(entry.target);
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.4 });

  statValues.forEach(el => observer.observe(el));
})();

/* ============================================================
   11. FAQ ACCORDION — Smooth height animation + + → × icon
   ============================================================ */
(function initFAQ() {
  const faqItems = document.querySelectorAll('.faq-item');
  if (!faqItems.length) return;

  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    if (!questionBtn) return;

    questionBtn.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      // Close all
      faqItems.forEach(i => i.classList.remove('open'));
      // Open if was closed
      if (!isOpen) item.classList.add('open');
    });
  });
})();

/* ============================================================
   12. DOWNLOAD MODAL — Slide-in with keyboard/backdrop dismiss
   ============================================================ */
(function initModal() {
  const downloadBtns = document.querySelectorAll('.open-download-modal');
  const modalOverlay = document.getElementById('download-modal');
  const modalClose   = document.getElementById('modal-close');
  if (!modalOverlay) return;

  function openModal() {
    modalOverlay.classList.add('active');
    document.body.style.overflow = 'hidden';
  }

  function closeModal() {
    modalOverlay.classList.remove('active');
    document.body.style.overflow = '';
  }

  downloadBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      openModal();
    });
  });

  if (modalClose) modalClose.addEventListener('click', closeModal);

  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) closeModal();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modalOverlay.classList.contains('active')) closeModal();
  });
})();

/* ============================================================
   13. RIPPLE EFFECT — On all .btn clicks
   ============================================================ */
(function initRipple() {
  document.querySelectorAll('.btn').forEach(btn => {
    btn.addEventListener('click', function (e) {
      const rect = btn.getBoundingClientRect();
      const size = Math.max(rect.width, rect.height) * 1.6;
      const x    = e.clientX - rect.left - size / 2;
      const y    = e.clientY - rect.top  - size / 2;

      const ripple = document.createElement('span');
      ripple.classList.add('ripple');
      ripple.style.cssText = `width:${size}px;height:${size}px;left:${x}px;top:${y}px;`;
      btn.appendChild(ripple);

      ripple.addEventListener('animationend', () => ripple.remove());
    });
  });
})();

/* ============================================================
   14. MAGNETIC BUTTON EFFECT — Subtle pull toward cursor
   ============================================================ */
(function initMagneticButtons() {
  const magneticBtns = document.querySelectorAll('.btn-primary, .btn-secondary');
  if (window.matchMedia('(pointer: coarse)').matches) return; // Skip on touch

  magneticBtns.forEach(btn => {
    btn.classList.add('btn-magnetic');

    btn.addEventListener('mousemove', (e) => {
      const rect = btn.getBoundingClientRect();
      const cx = rect.left + rect.width  / 2;
      const cy = rect.top  + rect.height / 2;
      const dx = (e.clientX - cx) * 0.22;
      const dy = (e.clientY - cy) * 0.22;
      btn.style.transform = `translate(${dx}px, ${dy}px)`;
    });

    btn.addEventListener('mouseleave', () => {
      btn.style.transform = '';
    });
  });
})();

/* ============================================================
   15. CARD TILT — 3D perspective transform on [data-tilt] elements
   ============================================================ */
(function initCardTilt() {
  const tiltEls = document.querySelectorAll('[data-tilt]');
  if (!tiltEls.length) return;
  if (window.matchMedia('(pointer: coarse)').matches) return;

  const INTENSITY = 8; // degrees
  const SCALE     = 1.02;

  tiltEls.forEach(el => {
    el.style.willChange = 'transform';

    el.addEventListener('mousemove', (e) => {
      const rect = el.getBoundingClientRect();
      const x    = (e.clientX - rect.left) / rect.width  - 0.5; // -0.5 to 0.5
      const y    = (e.clientY - rect.top)  / rect.height - 0.5;

      const rotateX = -y * INTENSITY;
      const rotateY =  x * INTENSITY;

      el.style.transform = `perspective(900px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale(${SCALE})`;
    });

    el.addEventListener('mouseleave', () => {
      el.style.transform = 'perspective(900px) rotateX(0deg) rotateY(0deg) scale(1)';
    });
  });
})();

/* ============================================================
   16. HOW-IT-WORKS STEP HOVER — card glow color cycle on hover
   ============================================================ */
(function initHowStepsHover() {
  const steps = document.querySelectorAll('.how-step');
  const colors = [
    'rgba(99,102,241,0.15)',   // Indigo
    'rgba(16,185,129,0.15)',   // Emerald
    'rgba(139,92,246,0.15)',   // Violet
  ];

  steps.forEach((step, i) => {
    step.addEventListener('mouseenter', () => {
      step.style.boxShadow = `0 20px 40px rgba(0,0,0,0.4), 0 0 28px ${colors[i % colors.length]}`;
    });
    step.addEventListener('mouseleave', () => {
      step.style.boxShadow = '';
    });
  });
})();

/* ============================================================
   17. SPEC CARD TILT (Bento grid)
   ============================================================ */
(function initSpecCardTilt() {
  const cards = document.querySelectorAll('.spec-card');
  if (!cards.length || window.matchMedia('(pointer: coarse)').matches) return;

  const INTENSITY = 5;

  cards.forEach(card => {
    card.style.willChange = 'transform';
    card.style.transition = 'transform 0.25s cubic-bezier(0.16,1,0.3,1), border-color 0.18s, box-shadow 0.35s';

    card.addEventListener('mousemove', (e) => {
      const rect   = card.getBoundingClientRect();
      const x      = (e.clientX - rect.left) / rect.width  - 0.5;
      const y      = (e.clientY - rect.top)  / rect.height - 0.5;
      const rotX   = -y * INTENSITY;
      const rotY   =  x * INTENSITY;
      card.style.transform = `perspective(700px) rotateX(${rotX}deg) rotateY(${rotY}deg) translateY(-5px)`;
    });

    card.addEventListener('mouseleave', () => {
      card.style.transform = '';
    });
  });
})();

/* ============================================================
   18. PLATFORM CARD HOVER GLOW (Download modal)
   ============================================================ */
(function initPlatformCardGlow() {
  document.querySelectorAll('.platform-card').forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const x    = ((e.clientX - rect.left) / rect.width)  * 100;
      const y    = ((e.clientY - rect.top)  / rect.height) * 100;
      card.style.background = `radial-gradient(circle at ${x}% ${y}%, rgba(99,102,241,0.14), var(--bg-card-hover) 60%)`;
    });
    card.addEventListener('mouseleave', () => {
      card.style.background = '';
    });
  });
})();

/* ============================================================
   19. SMOOTH SCROLL FOR ALL ANCHOR LINKS
   ============================================================ */
(function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const hash = anchor.getAttribute('href');
      if (!hash || hash === '#') return;

      const target = document.querySelector(hash);
      if (target) {
        e.preventDefault();
        const offset = 80; // height of sticky navbar
        const top = target.getBoundingClientRect().top + window.scrollY - offset;
        window.scrollTo({ top, behavior: 'smooth' });
      }
    });
  });
})();

/* ============================================================
   20. DOMContentLoaded — final setup pass
   ============================================================ */
document.addEventListener('DOMContentLoaded', () => {
  // Make first FAQ item open indicator correct on load
  const firstFaq = document.querySelector('.faq-item.open');
  if (firstFaq) {
    // Already handled via CSS .faq-item.open .faq-answer styles
  }

  // Trigger initial slider track fill color
  const slider = document.getElementById('storage-slider');
  if (slider) {
    slider.dispatchEvent(new Event('input'));
  }

  // Add staggered reveal delay to how-step cards
  document.querySelectorAll('.how-step').forEach((el, i) => {
    el.style.setProperty('--delay', `${i * 120}ms`);
  });

  // Add staggered reveal delay to spec cards
  document.querySelectorAll('.spec-card').forEach((el, i) => {
    // Slight offset per card within the bento grid
    el.style.transitionDelay = `${i * 60}ms`;
  });

  // Lazy-load images with a subtle fade-in
  const lazyImgs = document.querySelectorAll('img[loading="lazy"]');
  lazyImgs.forEach(img => {
    img.style.opacity = '0';
    img.style.transition = 'opacity 0.5s ease';
    img.addEventListener('load', () => {
      img.style.opacity = '1';
    });
    // If already cached / loaded
    if (img.complete) img.style.opacity = '1';
  });

  // Eagerly-loaded hero images should not fade
  document.querySelectorAll('img[loading="eager"]').forEach(img => {
    img.style.opacity = '1';
  });
});
