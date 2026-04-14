function bindAdminHomeEvents() {
  const logoutButton = document.getElementById('logout-btn');
  if (logoutButton) {
    logoutButton.addEventListener('click', () => {
      adminLogout();
    });
  }
}

async function loadAdminHomeHealth() {
  const roomCount = document.getElementById('room-count');
  const serverStatus = document.getElementById('server-status');

  try {
    const response = await fetch('/health');
    const data = await response.json();
    if (roomCount) {
      roomCount.textContent = String(data.rooms ?? 0);
    }
  } catch {
    if (roomCount) {
      roomCount.textContent = '?';
    }
    if (serverStatus) {
      serverStatus.textContent = 'UNKNOWN';
    }
  }
}

bindAdminHomeEvents();

initAdminAuth({
  redirectUnauthenticatedTo: getAdminLoginUrl('/admin-home'),
  onReady() {
    void loadAdminHomeHealth();
  },
});
