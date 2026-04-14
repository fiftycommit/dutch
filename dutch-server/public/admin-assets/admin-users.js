let currentPage = 1;

const $ = (id) => document.getElementById(id);
const api = adminFetch;

function bindAdminUsersEvents() {
  const logoutButton = $('logout-btn');
  const searchInput = $('search-input');
  const searchButton = $('search-button');
  const usersTableBody = $('users-tbody');
  const pagination = $('pagination');
  const modalOverlay = $('user-modal');
  const modalActions = $('modal-actions');

  logoutButton?.addEventListener('click', () => {
    adminLogout();
  });

  searchInput?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      void loadUsers(1);
    }
  });

  searchButton?.addEventListener('click', () => {
    void loadUsers(1);
  });

  usersTableBody?.addEventListener('click', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const button = target.closest('[data-user-id]');
    if (!(button instanceof HTMLElement)) {
      return;
    }

    const userId = Number(button.dataset.userId);
    if (!Number.isFinite(userId)) {
      return;
    }

    void openUser(userId);
  });

  pagination?.addEventListener('click', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const button = target.closest('[data-page]');
    if (!(button instanceof HTMLElement)) {
      return;
    }

    const page = Number(button.dataset.page);
    if (!Number.isFinite(page)) {
      return;
    }

    void loadUsers(page);
  });

  modalOverlay?.addEventListener('click', (event) => {
    if (event.target === modalOverlay) {
      closeModal();
      return;
    }

    const target = event.target;
    if (!(target instanceof HTMLElement)) {
      return;
    }

    const actionButton = target.closest('[data-modal-action]');
    if (!(actionButton instanceof HTMLElement)) {
      return;
    }

    const action = actionButton.dataset.modalAction;
    const userId = Number(actionButton.dataset.userId);
    const username = actionButton.dataset.username ?? '';

    if (action === 'close') {
      closeModal();
      return;
    }

    if (!Number.isFinite(userId)) {
      return;
    }

    if (action === 'ban') {
      void banUser(userId);
      return;
    }

    if (action === 'unban') {
      void unbanUser(userId);
      return;
    }

    if (action === 'delete') {
      void deleteUser(userId, username);
    }
  });
}

initAdminAuth({
  redirectUnauthenticatedTo: getAdminLoginUrl('/admin'),
  onReady() {
    bindAdminUsersEvents();
    void loadStats();
    void loadUsers(1);
  },
});

async function loadStats() {
  const { stats } = await api('/api/admin/stats');
  $('stat-total').textContent = stats.totalUsers;
  $('stat-banned').textContent = stats.bannedUsers;
  $('stat-recent').textContent = stats.recentUsers;
}

async function loadUsers(page = 1) {
  currentPage = page;
  const search = $('search-input').value.trim();
  const qs = new URLSearchParams({ page: String(page), limit: '50' });
  if (search) {
    qs.set('search', search);
  }

  const { users, pagination } = await api(`/api/admin/users?${qs}`);
  const tbody = $('users-tbody');
  tbody.innerHTML = users.map((user) => `
      <tr>
        <td>${user.id}</td>
        <td><strong>${esc(user.username)}</strong></td>
        <td>${esc(user.displayName)}</td>
        <td>${esc(user.email || '—')}</td>
        <td>${fmtDate(user.createdAt)}</td>
        <td>${user.lastLoginAt ? fmtDate(user.lastLoginAt) : '—'}</td>
        <td>${user.isBanned ? '<span class="badge badge-ban">Banni</span>' : '<span class="badge badge-ok">Actif</span>'}</td>
        <td><button class="btn btn-ghost btn-sm" data-user-id="${user.id}">Voir</button></td>
      </tr>
    `).join('');

  const pg = $('pagination');
  pg.innerHTML = '';
  for (let index = 1; index <= pagination.totalPages; index += 1) {
    const button = document.createElement('button');
    button.className = `btn btn-sm ${index === page ? 'btn-primary' : 'btn-ghost'}`;
    button.dataset.page = String(index);
    button.textContent = String(index);
    pg.appendChild(button);
  }
}

async function openUser(id) {
  const { user } = await api(`/api/admin/users/${id}`);
  $('modal-title').textContent = `@${user.username}`;
  $('modal-body').innerHTML = `
      <div class="detail-row"><span class="label">ID</span><span>${user.id}</span></div>
      <div class="detail-row"><span class="label">Pseudo</span><span>${esc(user.displayName)}</span></div>
      <div class="detail-row"><span class="label">Email</span><span>${esc(user.email || '—')}</span></div>
      <div class="detail-row"><span class="label">Créé le</span><span>${fmtDate(user.createdAt)}</span></div>
      <div class="detail-row"><span class="label">Dernière connexion</span><span>${user.lastLoginAt ? fmtDate(user.lastLoginAt) : '—'}</span></div>
      <div class="detail-row"><span class="label">Amis</span><span>${user.friendCount}</span></div>
      <div class="detail-row"><span class="label">Statut</span><span>${user.isBanned ? '<span class="badge badge-ban">Banni</span>' : '<span class="badge badge-ok">Actif</span>'}</span></div>
    `;

  const escapedUsername = esc(user.username);
  $('modal-actions').innerHTML = `
      <button class="btn btn-ghost btn-sm" data-modal-action="close">Fermer</button>
      ${user.isBanned
        ? `<button class="btn btn-success btn-sm" data-modal-action="unban" data-user-id="${user.id}">Débannir</button>`
        : `<button class="btn btn-danger btn-sm" data-modal-action="ban" data-user-id="${user.id}">Bannir</button>`
      }
      <button
        class="btn btn-danger btn-sm"
        data-modal-action="delete"
        data-user-id="${user.id}"
        data-username="${escapedUsername}"
      >Supprimer</button>
    `;

  $('user-modal').classList.add('active');
}

function closeModal() {
  $('user-modal').classList.remove('active');
}

async function banUser(id) {
  if (!confirm('Bannir cet utilisateur ?')) {
    return;
  }

  await api(`/api/admin/users/${id}/ban`, { method: 'POST' });
  closeModal();
  await loadStats();
  await loadUsers(currentPage);
}

async function unbanUser(id) {
  if (!confirm('Débannir cet utilisateur ?')) {
    return;
  }

  await api(`/api/admin/users/${id}/unban`, { method: 'POST' });
  closeModal();
  await loadStats();
  await loadUsers(currentPage);
}

async function deleteUser(id, username) {
  if (!confirm(`Supprimer définitivement @${username} et toutes ses données ?`)) {
    return;
  }

  await api(`/api/admin/users/${id}`, { method: 'DELETE' });
  closeModal();
  await loadStats();
  await loadUsers(currentPage);
}

function esc(value) {
  const div = document.createElement('div');
  div.textContent = value;
  return div.innerHTML;
}

function fmtDate(iso) {
  if (!iso) {
    return '—';
  }

  const date = new Date(`${iso}Z`);
  return date.toLocaleDateString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }) + ' ' + date.toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}
