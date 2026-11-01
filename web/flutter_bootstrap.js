{{flutter_js}}
{{flutter_build_config}}

const flutterServiceWorkerVersion = {{flutter_service_worker_version}};

function handleServiceWorkerUpdates() {
  if (!('serviceWorker' in navigator)) {
    return;
  }

  const hadControllerAtStartup = Boolean(navigator.serviceWorker.controller);
  let reloadTriggered = false;

  const triggerReloadOnce = function () {
    if (reloadTriggered) {
      return;
    }
    reloadTriggered = true;
    window.location.reload();
  };

  const activateWaitingWorker = function (worker) {
    if (!worker) {
      return;
    }
    worker.postMessage('skipWaiting');
  };

  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!hadControllerAtStartup) {
      return;
    }

    triggerReloadOnce();
  });

  // Register only after the first screen has had time to load. The worker
  // precaches the offline build and must not block or compete with startup.
  return function registerServiceWorker() {
    window.setTimeout(() => {
      navigator.serviceWorker.register(
        "/dutch_service_worker.js?v=" + flutterServiceWorkerVersion,
      ).then((registration) => {
        if (registration.waiting && navigator.serviceWorker.controller) {
          activateWaitingWorker(registration.waiting);
        }

        registration.addEventListener('updatefound', () => {
          const installingWorker = registration.installing;
          if (!installingWorker) {
            return;
          }

          installingWorker.addEventListener('statechange', () => {
            if (installingWorker.state === 'installed' && navigator.serviceWorker.controller) {
              activateWaitingWorker(registration.waiting || installingWorker);
            }
          });
        });
      }).catch(() => {});
    }, 15000);
  };
}

const registerServiceWorker = handleServiceWorkerUpdates();

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "/canvaskit/",
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      renderer: "canvaskit",
    });
    await appRunner.runApp();
    if (registerServiceWorker) {
      registerServiceWorker();
    }
    if (typeof window.flutterReady === "function") {
      window.flutterReady();
    }
  },
});
