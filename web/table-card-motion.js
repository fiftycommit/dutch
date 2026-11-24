(() => {
  const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
  const hands = new WeakMap();
  const drawnCards = new WeakMap();
  const easeInOut = 'cubic-bezier(.42, 0, .58, 1)';
  const easeOutCubic = 'cubic-bezier(.215, .61, .355, 1)';
  const zoomIcon = 'M15 3l2.3 2.3-2.89 2.87 1.42 1.42L18.7 6.7 21 9V3zM3 9l2.3-2.3 2.87 2.89 1.42-1.42L6.7 5.3 9 3H3zm6 12l-2.3-2.3 2.89-2.87-1.42-1.42L5.3 17.3 3 15v6zm12-6l-2.3 2.3-2.87-2.89-1.42 1.42 2.89 2.87L15 21h6z';
  const eyeIcon = 'M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zm0 12.5a5 5 0 1 1 0-10 5 5 0 0 1 0 10zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6z';

  function node(tag, className) {
    const element = document.createElement(tag);
    element.className = className;
    return element;
  }

  function initialize(root, mode) {
    root.classList.add('dutch-table-motion', mode);
    root.setAttribute('aria-hidden', 'true');
    Object.assign(root.style, {
      width: '100%', height: '100%', position: 'absolute', inset: '0', pointerEvents: 'none',
    });
  }

  function cardImage(asset) {
    const picture = node('div', 'dutch-table-card-image');
    const img = new Image();
    img.alt = '';
    img.decoding = 'async';
    if (asset) setImage(img, asset);
    picture.append(img);
    return { picture, img };
  }

  function setImage(img, asset) {
    img.src = new URL('assets/' + asset, document.baseURI).href;
  }

  function addHandCard(root, asset) {
    const slot = node('div', 'dutch-table-shuffle-slot');
    const card = node('div', 'dutch-table-shake-card');
    const { picture } = cardImage(asset);
    card.append(picture);
    slot.append(card);
    root.append(slot);
    return { slot, card, accent: '', shake: null, shuffle: null };
  }

  function updateHand(root, json) {
    const data = JSON.parse(json);
    let hand = hands.get(root);
    if (!hand) {
      initialize(root, 'dutch-table-hand');
      hand = { slots: [], generation: 0 };
      hands.set(root, hand);
    }
    const reduce = data.reduceMotion || motionPreference.matches;
    const elapsed = Math.max(0, Date.now() - data.shuffleStartedAt);
    const activeShuffle = data.shuffle !== 0 && elapsed < data.shuffleMs;
    const startShuffle = activeShuffle && data.shuffle !== hand.generation;
    hand.generation = data.shuffle;
    root.style.setProperty('--dutch-table-radius', `${data.radius}px`);
    root.style.setProperty('--dutch-hand-width', `${data.width}px`);
    root.style.setProperty('--dutch-hand-pad', `${data.padding}px`);

    while (hand.slots.length > data.cards.length) {
      const old = hand.slots.pop();
      old.shake?.cancel();
      old.shuffle?.cancel();
      old.slot.remove();
    }

    for (let i = 0; i < data.cards.length; i++) {
      const [sameCard, hidden, accent, firstMove, secondMove] = data.cards[i];
      let item = hand.slots[i];
      if (!item) {
        item = addHandCard(root, data.backAsset);
        hand.slots.push(item);
      }
      const { slot, card } = item;
      slot.style.left = `${data.padding + i * data.overlap}px`;
      slot.hidden = hidden;
      card.dataset.accent = accent;

      if (reduce || accent !== 'selected' || !sameCard) item.shake?.cancel();
      if (!reduce && accent === 'selected' && (item.accent !== accent || !sameCard)) {
        item.shake = card.animate([
          { transform: 'translateX(0)' },
          { transform: 'translateX(10px)' },
          { transform: 'translateX(0)' },
        ], 500);
      }
      item.accent = accent;

      if (reduce || startShuffle || !sameCard) item.shuffle?.cancel();
      if (reduce || !activeShuffle) continue;
      slot.style.setProperty('--dutch-hand-first', `${firstMove * data.overlap}px`);
      slot.style.setProperty('--dutch-hand-second', `${secondMove * data.overlap}px`);
      if (!startShuffle && sameCard) continue;
      item.shuffle = slot.animate([
        { transform: 'translateX(0)', easing: easeInOut, offset: 0 },
        { transform: 'translateX(var(--dutch-hand-first))', easing: easeInOut, offset: .33 },
        { transform: 'translateX(var(--dutch-hand-second))', easing: easeInOut, offset: .66 },
        { transform: 'translateX(0)', offset: 1 },
      ], data.shuffleMs);
      item.shuffle.currentTime = elapsed;
    }
  }

  function createDrawn(root) {
    initialize(root, 'dutch-table-drawn');
    const origin = node('div', 'dutch-table-drawn-origin');
    const frame = node('div', 'dutch-table-drawn-frame');
    const heading = node('div', 'dutch-table-drawn-heading');
    const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.setAttribute('viewBox', '0 0 24 24');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    icon.append(path);
    const label = node('span', 'dutch-table-drawn-label');
    const score = node('div', 'dutch-table-drawn-score');
    const { picture, img } = cardImage();
    heading.append(icon, label);
    frame.append(heading, picture, score);
    origin.append(frame);
    root.append(origin);
    return { frame, path, label, score, img, scale: null, animation: null };
  }

  function updateDrawn(root, json) {
    const data = JSON.parse(json);
    let drawn = drawnCards.get(root);
    if (!drawn) {
      drawn = createDrawn(root);
      drawnCards.set(root, drawn);
    }
    const reduce = data.reduceMotion || motionPreference.matches;
    const { frame, path, label, score, img } = drawn;
    const changedScale = data.scale !== drawn.scale;
    const canAnimate = changedScale && !reduce && drawn.scale !== null;
    // Lire la position seulement lors d'une inversion en cours de zoom.
    const start = canAnimate
      ? (drawn.animation?.playState === 'running'
        ? getComputedStyle(frame).transform : `scale(${drawn.scale})`)
      : null;
    if (changedScale || reduce) drawn.animation?.cancel();

    if (drawn.asset !== data.asset) {
      setImage(img, data.asset);
      drawn.asset = data.asset;
    }
    path.setAttribute('d', data.expanded ? eyeIcon : zoomIcon);
    label.textContent = data.label;
    score.textContent = data.score;
    root.toggleAttribute('data-compact', data.compact);
    frame.toggleAttribute('data-expanded', data.expanded);
    root.style.setProperty('--dutch-table-radius', `${data.radius}px`);
    root.style.setProperty('--dutch-drawn-card-width', `${data.width}px`);
    root.style.setProperty('--dutch-drawn-card-height', `${data.height}px`);
    root.style.setProperty('--dutch-drawn-font-size', `${data.fontSize}px`);
    root.style.setProperty('--dutch-drawn-line-height', data.lineHeight ?? 'normal');
    root.style.setProperty('--dutch-drawn-score-spacing', `${data.scoreSpacing}px`);
    root.style.setProperty('--dutch-drawn-base-size', `calc(${100 / data.safeScale}% - ${data.padding * 2}px)`);
    frame.style.setProperty('--dutch-drawn-scale', data.scale);
    drawn.scale = data.scale;

    if (canAnimate) {
      drawn.animation = frame.animate([
        { transform: start }, { transform: `scale(${data.scale})` },
      ], { duration: data.zoomMs, easing: easeOutCubic });
    }
  }

  if (typeof Element.prototype.animate === 'function') {
    window.dutchTableCardMotion = { updateHand, updateDrawn };
  }
})();
