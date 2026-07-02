(function () {
  function hideSplashBeforeFlutterBoot() {
    try {
      if (sessionStorage.getItem('dutch_room_code')) {
        document.write('<style>#splash{display:none!important}</style>');
      }
    } catch (_) {}
  }

  hideSplashBeforeFlutterBoot();

  var GAME_ROUTES = ['/game', '/memorization', '/results', '/dutch-reveal', '/setup'];

  function isGameRoute(path) {
    for (var index = 0; index < GAME_ROUTES.length; index += 1) {
      if (path.indexOf(GAME_ROUTES[index]) !== -1) {
        return true;
      }
    }
    return false;
  }

  function updateSafeBackgroundFromRoute() {
    var path = window.location.pathname + window.location.hash;
    var bg = isGameRoute(path)
      ? 'linear-gradient(to bottom, #0d2818, #1a472a)'
      : '#000000';
    document.documentElement.style.background = bg;
    document.body.style.background = bg;
  }

  updateSafeBackgroundFromRoute();
  window.addEventListener('popstate', updateSafeBackgroundFromRoute);

  var originalPushState = history.pushState.bind(history);
  history.pushState = function () {
    originalPushState.apply(history, arguments);
    updateSafeBackgroundFromRoute();
  };

  var originalReplaceState = history.replaceState.bind(history);
  history.replaceState = function () {
    originalReplaceState.apply(history, arguments);
    updateSafeBackgroundFromRoute();
  };

  window.setSafeBg = function (value) {
    document.documentElement.style.background = value;
    document.body.style.background = value;
    window._fixFlutterBg();
  };

  window._fixFlutterBg = function () {
    var flutterView = document.querySelector('flutter-view');
    if (!flutterView) {
      return;
    }

    flutterView.style.background = 'transparent';
    if (flutterView.shadowRoot) {
      var glassPane = flutterView.shadowRoot.querySelector('flt-glass-pane');
      if (glassPane) {
        glassPane.style.background = 'transparent';
      }

      if (!flutterView.shadowRoot.querySelector('[data-safe-bg-fix]')) {
        var style = document.createElement('style');
        style.textContent = ':host, flt-glass-pane { background: transparent !important; }';
        style.setAttribute('data-safe-bg-fix', '');
        flutterView.shadowRoot.appendChild(style);
      }
    }
  };

  new MutationObserver(function () {
    var flutterView = document.querySelector('flutter-view');
    if (!flutterView) {
      return;
    }

    window._fixFlutterBg();

    var viewport = document.querySelector('meta[name="viewport"]');
    if (viewport && viewport.content.indexOf('user-scalable=no') !== -1) {
      viewport.setAttribute('content', 'width=device-width, initial-scale=1.0');
    }

    if (flutterView.shadowRoot) {
      var glassPane = flutterView.shadowRoot.querySelector('flt-glass-pane');
      if (glassPane) {
        glassPane.style.touchAction = 'manipulation';
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });

  document.addEventListener('gesturestart', function () {}, { passive: true });
  document.addEventListener('gesturechange', function () {}, { passive: true });
  document.addEventListener('gestureend', function () {}, { passive: true });

  window.splashProgress = 0;
  window.splashStatus = '';
  window.flutterTookOver = false;
  window._lastSplashLogAt = 0;
  window.SPLASH_LOW_BANDWIDTH_DOWNLINK_Mbps = 1.5;

  window.isLowBandwidth = function () {
    var conn = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    if (!conn) {
      return false;
    }
    if (conn.saveData) {
      return true;
    }

    var type = conn.effectiveType || '';
    if (type === 'slow-2g' || type === '2g' || type === '3g') {
      return true;
    }

    var downlink = conn.downlink;
    return typeof downlink === 'number'
      && downlink > 0
      && downlink < window.SPLASH_LOW_BANDWIDTH_DOWNLINK_Mbps;
  };

  window.updateSplash = function (progress, status) {
    if (progress < window.splashProgress) {
      return;
    }

    window.splashProgress = progress;
    window.splashStatus = status || '';

    var statusEl = document.getElementById('splash-status');
    if (statusEl && status) {
      statusEl.textContent = status;
    }
  };

  window.hideSplash = function () {
    var splash = document.getElementById('splash');
    if (!splash) {
      return;
    }

    splash.classList.add('hidden');
    setTimeout(function () {
      splash.remove();
    }, 300);
  };

  window.flutterReady = function () {
    window.flutterTookOver = true;
    try {
      sessionStorage.removeItem('dutch_bootstrap_retries');
    } catch (_) {}
  };

  setTimeout(function () {
    if (window.flutterTookOver) {
      return;
    }

    var retryCount = 0;
    try {
      retryCount = parseInt(sessionStorage.getItem('dutch_bootstrap_retries') || '0', 10);
    } catch (_) {}

    if (retryCount < 3) {
      try {
        sessionStorage.setItem('dutch_bootstrap_retries', String(retryCount + 1));
      } catch (_) {}
      window.location.href = '/?cb=' + Date.now();
      return;
    }

    try {
      sessionStorage.removeItem('dutch_bootstrap_retries');
    } catch (_) {}

    var statusEl = document.getElementById('splash-status');
    if (statusEl) {
      statusEl.textContent = 'Chargement bloqué. Touchez pour relancer.';
    }

    var splash = document.getElementById('splash');
    if (splash) {
      splash.style.cursor = 'pointer';
      splash.onclick = function () {
        try {
          sessionStorage.removeItem('dutch_bootstrap_retries');
        } catch (_) {}
        window.location.href = '/?cb=' + Date.now();
      };
    }
  }, 20000);

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register(
        '/firebase-messaging-sw.js',
        { scope: '/firebase-cloud-messaging-push-scope' }
      ).catch(function () {
        // Push notifications are optional and must never block the app shell.
      });
    });
  }
}());
