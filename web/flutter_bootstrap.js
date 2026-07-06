{{flutter_js}}
{{flutter_build_config}}

const flutterServiceWorkerVersion = {{flutter_service_worker_version}};
const swReloadSessionKey = 'dutch_sw_reloaded_version';

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
    try {
      sessionStorage.setItem(swReloadSessionKey, String(flutterServiceWorkerVersion));
    } catch (_) {}
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

    let alreadyReloadedForThisVersion = false;
    try {
      alreadyReloadedForThisVersion =
        sessionStorage.getItem(swReloadSessionKey) === String(flutterServiceWorkerVersion);
    } catch (_) {}

    if (!alreadyReloadedForThisVersion) {
      triggerReloadOnce();
    }
  });

  navigator.serviceWorker.getRegistration().then((registration) => {
    if (!registration) {
      return;
    }

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

    registration.update().catch(() => {});
  });
}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: flutterServiceWorkerVersion,
    serviceWorkerUrl: "/dutch_service_worker.js?v=" + flutterServiceWorkerVersion,
  },
  onEntrypointLoaded: async function (engineInitializer) {
    handleServiceWorkerUpdates();
    const appRunner = await engineInitializer.initializeEngine({
      renderer: "canvaskit",
    });
    await appRunner.runApp();
    if (typeof window.flutterReady === "function") {
      window.flutterReady();
    }
    if (typeof window.hideSplash === "function") {
      window.hideSplash();
    }
  },
});
