(() => {
  const images = new Map();
  let active;

  function prepare(asset) {
    if (!images.has(asset)) {
      const image = new Image();
      image.src = new URL('assets/' + asset, document.baseURI).href;
      const decoded = image.decode();
      decoded.catch(() => {}); // show() observes this error if it needs this asset.
      images.set(asset, { image, decoded });
    }
    return images.get(asset);
  }

  function cancel() {
    active?.finish();
    images.clear();
  }

  async function show(assets, back) {
    active?.finish();
    const dialog = document.createElement('dialog');
    dialog.className = 'dutch-card-reveal';
    dialog.setAttribute('aria-labelledby', 'dutch-reveal-title');
    dialog.addEventListener('cancel', event => event.preventDefault());
    dialog.innerHTML = `<header><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zm0 12.5a5 5 0 1 1 0-10 5 5 0 0 1 0 10zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"/></svg><h2 id="dutch-reveal-title" tabindex="-1" autofocus>VOS CARTES</h2></header><div class="dutch-reveal-cards"></div><p>Mémorisez bien ces cartes !</p><div class="dutch-reveal-clock"><div><i></i></div><span>4s</span></div>`;
    let resolve;
    const completed = new Promise(done => { resolve = done; });
    let interval, hold, leave;
    const session = { finish() {
      clearInterval(interval);
      clearTimeout(hold);
      clearTimeout(leave);
      if (dialog.open) dialog.close();
      dialog.remove();
      if (active === session) active = undefined;
      resolve();
    } };
    active = session;
    try {
      const cards = dialog.querySelector('.dutch-reveal-cards');
      const decodes = [];
      function addImage(card, asset, side) {
        const source = prepare(asset);
        const image = source.image.cloneNode();
        image.className = side;
        image.alt = '';
        card.append(image);
        decodes.push(source.decoded, image.decode());
      }
      for (const asset of assets) {
        const card = document.createElement('div');
        card.className = asset === back ? 'dutch-reveal-card' : 'dutch-reveal-card dutch-reveal-flip';
        addImage(card, back, 'dutch-reveal-back');
        if (asset !== back) addImage(card, asset, 'dutch-reveal-front');
        cards.append(card);
      }
      await Promise.race([Promise.all(decodes), completed]);
      if (active !== session) return;
      document.body.append(dialog);
      dialog.showModal();
      let seconds = 4;
      const count = dialog.querySelector('.dutch-reveal-clock span');
      interval = setInterval(() => { count.textContent = `${--seconds}s`; }, 1000);
      hold = setTimeout(() => {
        clearInterval(interval);
        dialog.classList.add('dutch-reveal-closing');
        const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
        leave = setTimeout(session.finish, reduced ? 0 : 150);
      }, 4000);
      await completed;
    } finally {
      session.finish();
      if (!active) images.clear();
    }
  }

  function cubic(x, x1, y1, x2, y2) {
    const bezier = (a, b, t) => 3 * (1 - t) ** 2 * t * a +
      3 * (1 - t) * t ** 2 * b + t ** 3;
    let lo = 0, hi = 1;
    for (let i = 0; i < 18; i++) {
      const t = (lo + hi) / 2;
      if (bezier(x1, x2, t) < x) lo = t;
      else hi = t;
    }
    return x === 0 || x === 1 ? x : bezier(y1, y2, (lo + hi) / 2);
  }

  const flightFrames = Array.from({ length: 21 }, (_, i) => {
    const t = i / 20;
    return {
      t,
      distance: cubic(t, .215, .61, .355, 1),
      swapDistance: cubic(t, .645, .045, .355, 1),
      scale: 1 + .08 * (t <= .2 ? t / .2 : (1 - t) / .8),
    };
  });

  function fly(asset, x, y, dx, dy, width, height, duration, easeInOut, onDone) {
    const card = new Image();
    card.src = new URL('assets/' + asset, document.baseURI).href;
    card.className = 'dutch-card-flight';
    card.alt = '';
    card.setAttribute('aria-hidden', 'true');
    Object.assign(card.style, {
      left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px`,
    });
    let cancelled = false;
    let move, fade;
    const cancelFlight = () => {
      cancelled = true;
      move?.cancel();
      fade?.cancel();
      card.remove();
    };
    (async () => {
      let success = false;
      try {
        await card.decode();
        if (cancelled) return;
        if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
          document.body.append(card);
          move = card.animate(flightFrames.map(({ t, distance, swapDistance, scale }) => {
            const position = easeInOut ? swapDistance : distance;
            return {
              offset: t,
              transform: `translate(${dx * position}px,${dy * position}px) scale(${scale}) rotate(${.06 * distance}rad)`,
            };
          }), { duration, fill: 'both' });
          fade = card.animate([{ opacity: .7 }, { opacity: 1 }], {
            duration: duration * .3, easing: 'ease-out', fill: 'both',
          });
          await move.finished;
        }
        success = true;
      } finally {
        if (!cancelled) {
          cancelFlight();
          onDone(success);
        }
      }
    })().catch(() => {}); // Dart uses its existing flight if the browser fails.
    return cancelFlight;
  }

  window.dutchCardReveal = { prepare, show, cancel, fly };
})();
