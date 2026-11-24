(() => {
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  if (!Element.prototype.animate || !document.timeline ||
      !window.ResizeObserver || !window.IntersectionObserver || !motion.addEventListener) return;

  function mount(host, nextBatch, active) {
    host.className = 'dutch-card-rain';
    host.setAttribute('aria-hidden', 'true');
    Object.assign(host.style, {
      width: '100%', height: '100%', position: 'relative', overflow: 'hidden',
      pointerEvents: 'none', contain: 'layout paint',
    });

    const sprites = [];
    const animations = [];
    let width = 0;
    let height = 0;
    let inViewport = false;
    let running = false;
    let disposed = false;

    function showTrack(track, index) {
      let sprite = sprites[index];
      if (!sprite) {
        const image = new Image();
        image.alt = '';
        image.draggable = false;
        Object.assign(image.style, {
          position: 'absolute', top: '0', left: '0', objectFit: 'contain',
        });
        host.append(image);
        sprite = sprites[index] = { image };
      }
      if (sprite.asset !== track.asset) {
        sprite.asset = track.asset;
        sprite.image.src = 'assets/' + track.asset;
      }
      if (sprite.height !== track.height || sprite.opacity !== track.opacity) {
        sprite.height = track.height;
        sprite.opacity = track.opacity;
        Object.assign(sprite.image.style, {
          width: `${track.width}px`, height: `${track.height}px`, opacity: track.opacity,
        });
      }
      return sprite.image;
    }

    function canPlay() {
      return !disposed && active && inViewport && width > 0 && height > 0 &&
        !motion.matches && !document.hidden && host.isConnected;
    }

    function playBatch() {
      const batch = nextBatch(width, height);
      const startTime = document.timeline.currentTime;
      const stride = batch.tracks.length * 3;
      const first = animations[0];
      if (first) first.onfinish = null;
      for (let index = 0; index < batch.tracks.length; index++) {
        const track = batch.tracks[index];
        const image = showTrack(track, index);
        const frames = [];
        for (let frame = 0; frame < batch.frameCount; frame++) {
          const i = frame * stride + index * 3;
          const x = batch.frames[i].toFixed(3);
          const y = batch.frames[i + 1].toFixed(3);
          const angle = batch.frames[i + 2].toFixed(4);
          frames.push({
            offset: frame === batch.frameCount - 1 ? 1 : frame * batch.sampleInterval / batch.duration,
            transform: `translate(${x}px, ${y}px) rotate(${angle}rad)`,
          });
        }
        const animation = image.animate(frames, { duration: batch.duration, fill: 'both' });
        animation.startTime = startTime;
        animations[index]?.cancel();
        animations[index] = animation;
      }
      animations[0].onfinish = () => {
        if (canPlay()) playBatch();
      };
    }

    function updatePlayback() {
      const shouldPlay = canPlay();
      if (running === shouldPlay) return;
      running = shouldPlay;
      if (!running) {
        for (const animation of animations) {
          if (animation.playState !== 'finished') animation.pause();
        }
      } else if (!animations.length || animations[0].playState === 'finished') {
        playBatch();
      } else {
        for (const animation of animations) animation.play();
      }
    }

    function updateMotion() {
      host.style.visibility = motion.matches ? 'hidden' : '';
      updatePlayback();
    }

    const resize = new ResizeObserver(([entry]) => {
      ({ width, height } = entry.contentRect);
      updatePlayback();
    });
    const intersection = new IntersectionObserver(entries => {
      inViewport = entries[entries.length - 1].isIntersecting;
      updatePlayback();
    });
    resize.observe(host);
    intersection.observe(host);
    document.addEventListener('visibilitychange', updatePlayback);
    motion.addEventListener('change', updateMotion);
    updateMotion();

    return {
      setActive(value) {
        active = value;
        // reprendre apres le layout Flutter pour lire les obstacles a jour
        if (value) queueMicrotask(updatePlayback);
        else updatePlayback();
      },
      dispose() {
        disposed = true;
        intersection.disconnect();
        resize.disconnect();
        document.removeEventListener('visibilitychange', updatePlayback);
        motion.removeEventListener('change', updateMotion);
        if (animations.length) animations[0].onfinish = null;
        for (const animation of animations) animation.cancel();
        host.replaceChildren();
      },
    };
  }

  window.dutchCardRain = { mount };
})();
