// AeroDrive Interactive Website Scripts

document.addEventListener('DOMContentLoaded', () => {
  // 1. Interactive Tabs
  const tabButtons = document.querySelectorAll('.tab-btn');
  const tabContents = document.querySelectorAll('.tab-content');

  tabButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-tab');

      tabButtons.forEach(b => b.classList.remove('active'));
      tabContents.forEach(c => c.classList.remove('active'));

      btn.classList.add('active');
      const targetContent = document.getElementById(targetId);
      if (targetContent) {
        targetContent.classList.add('active');
      }
    });
  });

  // 2. Storage Savings Calculator
  const storageSlider = document.getElementById('storage-slider');
  const storageDisplay = document.getElementById('storage-display');
  const gdriveCost = document.getElementById('gdrive-cost');
  const dropboxCost = document.getElementById('dropbox-cost');
  const icloudCost = document.getElementById('icloud-cost');

  function updateCalculator() {
    if (!storageSlider) return;
    const gb = parseInt(storageSlider.value, 10);
    const tb = (gb / 1000).toFixed(1);

    // Display formatted
    if (gb >= 1000) {
      storageDisplay.textContent = `${tb.replace('.0', '')} TB`;
    } else {
      storageDisplay.textContent = `${gb} GB`;
    }

    // Pricing models (approx. standard commercial monthly pricing converted to annual)
    // Google One: ~ $20/yr (100GB), $30/yr (200GB), $100/yr (2TB), $250/yr (5TB), ~$50/TB/yr beyond
    let gCost = 0;
    if (gb <= 200) gCost = 30;
    else if (gb <= 2000) gCost = 100;
    else gCost = Math.round(100 + ((gb - 2000) / 1000) * 60);

    // Dropbox: 2TB = $120/yr, each additional TB approx $72/yr
    let dCost = 0;
    if (gb <= 2000) dCost = 120;
    else dCost = Math.round(120 + ((gb - 2000) / 1000) * 72);

    // iCloud: 2TB = $120/yr, 6TB = $360/yr, 12TB = $720/yr
    let iCost = 0;
    if (gb <= 200) iCost = 36;
    else if (gb <= 2000) iCost = 120;
    else iCost = Math.round(120 + ((gb - 2000) / 1000) * 65);

    if (gdriveCost) gdriveCost.textContent = `$${gCost}`;
    if (dropboxCost) dropboxCost.textContent = `$${dCost}`;
    if (icloudCost) icloudCost.textContent = `$${iCost}`;
  }

  if (storageSlider) {
    storageSlider.addEventListener('input', updateCalculator);
    updateCalculator();
  }

  // 3. Flow Step Cards
  const flowCards = document.querySelectorAll('.flow-step-card');
  flowCards.forEach(card => {
    card.addEventListener('mouseenter', () => {
      flowCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
    });
  });

  // 4. FAQ Accordion
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    if (questionBtn) {
      questionBtn.addEventListener('click', () => {
        const isOpen = item.classList.contains('open');
        // Close others
        faqItems.forEach(i => i.classList.remove('open'));
        if (!isOpen) {
          item.classList.add('open');
        }
      });
    }
  });

  // 5. Download Modal
  const downloadBtns = document.querySelectorAll('.open-download-modal');
  const modalOverlay = document.getElementById('download-modal');
  const modalClose = document.getElementById('modal-close');

  downloadBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      if (modalOverlay) modalOverlay.classList.add('active');
    });
  });

  if (modalClose && modalOverlay) {
    modalClose.addEventListener('click', () => {
      modalOverlay.classList.remove('active');
    });

    modalOverlay.addEventListener('click', (e) => {
      if (e.target === modalOverlay) {
        modalOverlay.classList.remove('active');
      }
    });
  }

  // 6. Escape Key Listener
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modalOverlay && modalOverlay.classList.contains('active')) {
      modalOverlay.classList.remove('active');
    }
  });
});
