(() => {
  if (typeof Element.prototype.animate !== 'function' ||
      typeof Animation === 'undefined' || !('finished' in Animation.prototype) ||
      typeof HTMLImageElement.prototype.decode !== 'function' ||
      !window.CSS?.supports('transform-style', 'preserve-3d') ||
      !window.CSS.supports('backface-visibility', 'hidden')) return;

  // Le signe de la perspective CSS est inverse de celui de Matrix4.
  const flipFrames = [
    { transform: 'perspective(1000px) rotateY(0deg)' },
    { transform: 'perspective(1000px) rotateY(-180deg)' },
  ];
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');

  window.dutchRoundReveal = function createGrid(host, faceUrls, backUrl) {
    host.className = 'dutch-round-reveal';
    host.hidden = true;
    host.setAttribute('aria-hidden', 'true');
    const grid = document.createDocumentFragment();
    const rows = [];
    const images = [];
    let ready = false;
    let disposed = false;
    let revealedThrough = -1;
    let active = [];

    function image(url, side) {
      const img = new Image();
      img.className = `dutch-round-reveal-face dutch-round-reveal-${side}`;
      img.alt = '';
      img.src = url;
      images.push(img.decode());
      return img;
    }

    for (const faceRow of faceUrls) {
      const row = document.createElement('div');
      row.className = 'dutch-round-reveal-row';
      const cards = [];
      for (const face of faceRow) {
        const cell = document.createElement('div');
        cell.className = 'dutch-round-reveal-cell';
        row.append(cell);
        if (face === null) continue;

        const card = document.createElement('div');
        card.className = 'dutch-round-reveal-card';
        card.append(image(backUrl, 'back'), image(face, 'front'));
        cell.append(card);
        cards.push(card);
      }
      rows.push(cards);
      grid.append(row);
    }
    host.append(grid);
    Promise.all(images).then(() => { ready = !disposed; }, () => {});

    function showCards(through) {
      while (revealedThrough < through) {
        for (const card of rows[++revealedThrough]) card.classList.add('is-revealed');
      }
    }

    function cancelAnimations() {
      for (const animation of active) animation.cancel();
      active = [];
    }

    function flip(index, duration, reducedMotion) {
      if (!ready || !host.isConnected || !rows[index]) return null;
      if (host.hidden && getComputedStyle(host)
        .getPropertyValue('--dutch-round-styles-ready').trim() !== '1') return null;

      showCards(index - 1);
      host.hidden = false;
      if (reducedMotion || motion.matches) {
        showCards(index);
        return Promise.resolve(true);
      }

      const cards = rows[index];
      const finished = [];
      try {
        for (const card of cards) {
          card.classList.add('is-flipping');
          const animation = card.animate(flipFrames, { duration, fill: 'both' });
          active.push(animation);
          finished.push(animation.finished.then(() => true, () => false));
        }
      } catch {
        dispose();
        return null;
      }
      return Promise.all(finished).then(results => {
        if (disposed) return false;
        if (results.includes(false)) {
          dispose();
          return false;
        }
        showCards(index);
        for (const card of cards) card.classList.remove('is-flipping');
        cancelAnimations();
        return true;
      });
    }

    function dispose() {
      disposed = true;
      ready = false;
      cancelAnimations();
      host.hidden = true;
      host.replaceChildren();
    }

    return { flip, dispose };
  };
})();
