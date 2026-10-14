<script>
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';

  const inGame = typeof window.GetParentResourceName === 'function';
  let visible = !inGame;
  let uiMode = 'admin';
  let ready = false;
  let loading = false;
  let loginRequired = false;
  let loginUrl = '/login';
  let csrf = '';
  let page = 'dashboard';
  let sidebarOpen = false;
  let compactMode = false;
  let data = { server: {}, admin: {}, players: [], history: [], teleports: [], roles: [], banDurations: [], accounts: [] };
  let players = [];
  let characters = [];
  let reports = [];
  let items = [];
  let vehicles = [];
  let bans = [];
  let logs = [];
  let resources = [];
  let staff = [];
  let analytics = { totals: {}, economy: [], actions: [], duty: [] };
  let selfStates = {};
  let selectedPlayer = null;
  let selectedReport = null;
  let playerDetails = null;
  let reportDetails = null;
  let playerReports = [];
  let playerReportCategories = [];
  let playerReportMaxOpen = 3;
  let selectedPlayerReport = null;
  let playerReportDetails = null;
  let playerReportReady = false;
  let playerReportLoading = false;
  let reportComposer = true;
  let reportReply = '';
  let newReport = { category: 'general', subject: '', message: '' };
  let query = '';
  let includeClosed = false;
  let modal = null;
  let toasts = [];
  let refreshTimer;

  const nav = [
    { id: 'dashboard', label: 'Dashboard', icon: 'grid', permission: 'dashboard.view' },
    { id: 'analytics', label: 'Analytics', icon: 'activity', permission: 'analytics.view' },
    { id: 'players', label: 'Players', icon: 'users', permission: 'players.view', count: () => players.length },
    { id: 'characters', label: 'Characters', icon: 'users', permission: 'characters.view' },
    { id: 'reports', label: 'Reports', icon: 'report', permission: 'reports.view', count: () => reports.filter(r => r.status !== 'closed').length },
    { id: 'items', label: 'Items', icon: 'box', permission: 'items.view' },
    { id: 'vehicles', label: 'Vehicles', icon: 'car', permission: 'vehicles.view' },
    { id: 'bans', label: 'Bans', icon: 'ban', permission: 'bans.view' },
    { id: 'server', label: 'Server', icon: 'server', permission: 'server.view' },
    { id: 'logs', label: 'Audit logs', icon: 'logs', permission: 'logs.view' },
    { id: 'staff', label: 'Staff & roles', icon: 'shield', permission: 'staff.manage' }
  ];

  const pageTitles = {
    dashboard: ["The Harbourmaster's Ledger", 'A live account of your city and its systems'], players: ['Who Sails Tonight?', 'Manage everyone currently in the city'],
    analytics: ['City Intelligence', 'Economy, workload and staff activity across SeaM'],
    characters: ['The City Register', 'Search the SeaM Core character archive'], reports: ['Signals & Reports', 'Answer support calls from across the city'], items: ["Quartermaster's Ledger", 'Search and grant SeaM Inventory cargo'],
    vehicles: ['The Motor Pool', 'Find registered vehicles and launch models'], bans: ['The Blacklist', 'Review and revoke active city bans'], server: ['City Command', 'Weather, time, announcements and resources'],
    logs: ["Captain's Log", 'Every administrative action on record'], staff: ["The Officer's Roll", 'Manage identifier roles for browser and in-city access']
  };

  function has(permission) {
    const permissions = data.admin?.permissions || {};
    return permissions['*'] === true || permissions[permission] === true;
  }

  async function nuiPost(route, payload = {}) {
    const resource = window.GetParentResourceName();
    const response = await fetch(`https://${resource}/${route}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
    });
    return response.json();
  }

  async function rpc(action, payload = {}, quiet = false) {
    try {
      const result = inGame
        ? await nuiPost('rpc', { action, payload })
        : await fetch('/api/rpc', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
            body: JSON.stringify({ action, payload })
          }).then(r => r.json());
      if (!result.ok && !quiet) toast(result.error || 'Action failed.', 'error');
      return result;
    } catch (error) {
      if (!quiet) toast('Could not reach the server.', 'error');
      return { ok: false, error: String(error) };
    }
  }

  async function playerReportRpc(action, payload = {}, quiet = false) {
    try {
      const result = await nuiPost('reportRpc', { action, payload });
      if (!result.ok && !quiet) toast(result.error || 'Report action failed.', 'error');
      return result;
    } catch (error) {
      if (!quiet) toast('Could not reach the report server.', 'error');
      return { ok: false, error: String(error) };
    }
  }

  async function loadPlayerReportCenter(preferredId = null, preserveComposer = true) {
    if (playerReportLoading) return;
    playerReportLoading = true;
    try {
      const result = await playerReportRpc('bootstrap', {}, true);
      if (!result.ok) { toast(result.error || 'Could not load your reports.', 'error'); return; }
      playerReports = result.reports || [];
      playerReportCategories = result.categories || [];
      playerReportMaxOpen = Number(result.maxOpen) || 3;
      if (!playerReportCategories.find(entry => entry.id === newReport.category)) {
        newReport = { ...newReport, category: playerReportCategories[0]?.id || 'general' };
      }
      playerReportReady = true;
      const wantedId = Number(preferredId || selectedPlayerReport?.id || 0);
      const wanted = playerReports.find(report => Number(report.id) === wantedId);
      if (wanted && !preserveComposer) await openPlayerReport(wanted);
      else if (!preserveComposer) { selectedPlayerReport = null; playerReportDetails = null; reportComposer = true; }
    } finally { playerReportLoading = false; }
  }

  async function openPlayerReport(report) {
    reportComposer = false;
    selectedPlayerReport = report;
    playerReportDetails = null;
    const result = await playerReportRpc('details', { id: report.id });
    if (result.ok) {
      playerReportDetails = result;
      selectedPlayerReport = result.report;
    }
  }

  function openPlayerReportComposer() {
    reportComposer = true;
    selectedPlayerReport = null;
    playerReportDetails = null;
    reportReply = '';
  }

  async function submitPlayerReport() {
    const result = await playerReportRpc('create', newReport);
    if (!result.ok) return;
    toast(result.message || 'Report sent to staff.');
    const createdId = result.id;
    newReport = { category: playerReportCategories[0]?.id || 'general', subject: '', message: '' };
    reportComposer = false;
    await loadPlayerReportCenter(createdId, true);
    const created = playerReports.find(report => Number(report.id) === Number(createdId)) || { id: createdId };
    await openPlayerReport(created);
  }

  async function submitPlayerReportReply() {
    if (!selectedPlayerReport || !reportReply.trim()) return;
    const result = await playerReportRpc('reply', { id: selectedPlayerReport.id, message: reportReply });
    if (!result.ok) return;
    reportReply = '';
    toast(result.message || 'Reply sent.');
    await loadPlayerReportCenter(selectedPlayerReport.id, false);
  }

  async function closePlayerReport() {
    if (!selectedPlayerReport || !confirm(`Close report #${selectedPlayerReport.id}?`)) return;
    const id = selectedPlayerReport.id;
    const result = await playerReportRpc('close', { id });
    if (!result.ok) return;
    toast(result.message || 'Report closed.');
    await loadPlayerReportCenter(id, false);
  }

  function reportCategoryLabel(id) {
    return playerReportCategories.find(entry => entry.id === id)?.label || String(id || 'General support');
  }

  async function bootstrap() {
    if (loading) return;
    loading = true;
    try {
      let result;
      if (inGame) result = await rpc('bootstrap', {}, true);
      else {
        const response = await fetch('/api/bootstrap', { cache: 'no-store' });
        result = await response.json();
        if (response.status === 401) {
          loginRequired = true; loginUrl = result.loginUrl || '/login'; ready = true; return;
        }
      }
      if (!result.ok) { loginRequired = !inGame; toast(result.error || 'Access denied.', 'error'); return; }
      csrf = result.csrf || csrf;
      data = result;
      players = result.players || [];
      ready = true;
      loginRequired = false;
      await loadPage(page, true);
    } finally { loading = false; }
  }

  async function loadPage(next, quiet = false) {
    page = next; query = ''; sidebarOpen = false;
    if (next === 'players') { const r = await rpc('players.list', {}, quiet); if (r.ok) players = r.players || []; }
    if (next === 'analytics') { const r = await rpc('analytics.snapshot', {}, quiet); if (r.ok) analytics = r; }
    if (next === 'characters') { const r = await rpc('characters.list', { search: '' }, quiet); if (r.ok) characters = r.characters || []; }
    if (next === 'reports') { const r = await rpc('reports.list', { includeClosed }, quiet); if (r.ok) reports = r.reports || []; }
    if (next === 'items' && !items.length) { const r = await rpc('items.list', {}, quiet); if (r.ok) items = r.items || []; }
    if (next === 'vehicles' && !vehicles.length) { const r = await rpc('vehicles.list', {}, quiet); if (r.ok) vehicles = r.vehicles || []; }
    if (next === 'bans') { const r = await rpc('bans.list', { search: '' }, quiet); if (r.ok) bans = r.bans || []; }
    if (next === 'server') { const r = await rpc('server.resources', {}, quiet); if (r.ok) resources = r.resources || []; }
    if (next === 'logs') { const r = await rpc('logs.list', { search: '' }, quiet); if (r.ok) logs = r.logs || []; }
    if (next === 'staff') { const r = await rpc('staff.list', {}, quiet); if (r.ok) staff = r.staff || []; }
  }

  function toast(message, type = 'success') {
    const id = Date.now() + Math.random();
    toasts = [...toasts, { id, message, type }];
    setTimeout(() => toasts = toasts.filter(t => t.id !== id), 3500);
  }

  function toggleCompactMode() {
    compactMode = !compactMode;
    try { localStorage.setItem('seam-admin-compact', compactMode ? '1' : '0'); } catch (_) {}
  }

  async function doAction(action, payload = {}, message = 'Action completed.') {
    const result = await rpc(action, payload);
    if (result.ok) toast(message);
    return result;
  }

  async function toggleSelf(action) {
    const enabled = !selfStates[action];
    const result = await doAction('self.action', { action, enabled }, `${action.replaceAll('_', ' ')} ${enabled ? 'enabled' : 'disabled'}.`);
    if (result.ok) selfStates = { ...selfStates, [action]: enabled };
  }

  async function toggleDuty() {
    const enabled = !data.admin?.onDuty;
    const result = await doAction('staff.duty', { enabled }, enabled ? 'Admin duty started.' : 'Admin duty ended.');
    if (result.ok) {
      data = { ...data, admin: { ...data.admin, onDuty: result.onDuty } };
      if (!enabled) selfStates = {};
    }
  }

  async function openPlayer(player) {
    selectedPlayer = player; playerDetails = null;
    const result = await rpc('player.details', { target: player.source });
    if (result.ok) playerDetails = result;
  }

  async function playerAction(action, extra = {}, message = 'Player updated.') {
    if (!selectedPlayer) return;
    const result = await doAction(`player.${action}`, { target: selectedPlayer.source, ...extra }, message);
    if (result.ok && !['goto', 'bring', 'spectate', 'openInventory'].includes(action)) openPlayer(selectedPlayer);
  }

  async function openReport(report) {
    selectedReport = report; reportDetails = null;
    const result = await rpc('reports.details', { id: report.id });
    if (result.ok) reportDetails = result;
  }

  async function reportAction(action, payload = {}) {
    if (!selectedReport) return;
    const result = await doAction(`reports.${action}`, { id: selectedReport.id, ...payload }, 'Report updated.');
    if (result.ok) {
      const list = await rpc('reports.list', { includeClosed }, true); if (list.ok) reports = list.reports || [];
      if (action === 'close') { selectedReport = null; reportDetails = null; }
      else openReport(selectedReport);
    }
  }

  function openForm(type, context = {}) {
    const defaults = {
      warn: { reason: '' }, kick: { reason: '' }, ban: { reason: '', duration: 86400 },
      item: { target: context.target || '', item: context.item || '', amount: 1 },
      job: { job: '', grade: 0 }, money: { operation: 'add', account: data.accounts?.[0]?.name || 'cash', amount: 1000 },
      announcement: { message: '' }, vehicle: { model: '' }, note: { note: '' },
      armour: { amount: 100 }, needs: { hunger: 100, thirst: 100, stress: 0 },
      model: { model: '' }, message: { message: '' },
      removeItem: { item: context.name || '', amount: context.count || 1, slot: context.slot || 0 },
      coords: { x: '', y: '', z: '', w: '' }, clearArea: { entityType: 'all', radius: 25 },
      staff: {
        id: context.id || 0, name: context.name || '', role: context.role || 'support',
        license: context.license || '', license2: context.license2 || '', discordId: context.discord_id || '',
        fivem: context.fivem || '', steam: context.steam || '', xbl: context.xbl || '', live: context.live || ''
      }
    };
    modal = { type, values: defaults[type], context };
  }

  function modalTitle(entry) {
    if (!entry) return '';
    if (entry.type === 'staff') return entry.values.id ? 'Edit staff member' : 'Add staff member';
    return ({ item: 'Give item', job: 'Set player job', money: 'Manage money', announcement: 'City announcement',
      vehicle: 'Spawn vehicle model', note: 'Add staff note', armour: 'Set player armour', needs: 'Set player needs',
      model: 'Change pedestrian model', message: 'Private staff message', removeItem: 'Remove inventory item',
      coords: 'Teleport to coordinates', clearArea: 'Clear nearby entities' })[entry.type]
      || `${entry.type[0].toUpperCase() + entry.type.slice(1)} player`;
  }

  async function submitModal() {
    if (!modal) return;
    const { type, values } = modal;
    let result;
    if (type === 'warn' || type === 'kick' || type === 'ban') result = await playerAction(type, values, `${type[0].toUpperCase() + type.slice(1)} applied.`);
    if (type === 'item') result = await doAction('player.giveItem', values, 'Item granted.');
    if (type === 'job') result = await playerAction('setJob', values, 'Job updated.');
    if (type === 'money') result = await playerAction('money', values, 'Money updated.');
    if (type === 'note') result = await playerAction('note', values, 'Staff note added.');
    if (type === 'armour') result = await playerAction('armour', values, 'Armour updated.');
    if (type === 'needs') result = await playerAction('needs', values, 'Player needs updated.');
    if (type === 'model') result = await playerAction('setModel', values, 'Player model updated.');
    if (type === 'message') result = await playerAction('message', values, 'Private staff message sent.');
    if (type === 'removeItem') result = await playerAction('removeItem', values, 'Inventory item removed.');
    if (type === 'announcement') result = await doAction('server.announce', values, 'Announcement sent.');
    if (type === 'vehicle') result = await doAction('vehicle.action', { action: 'spawn', model: values.model }, 'Vehicle spawned.');
    if (type === 'coords') result = await doAction('self.teleportCoords', values, 'Teleported to coordinates.');
    if (type === 'clearArea') result = await doAction('server.clearArea', values, 'Clear-area request sent.');
    if (type === 'staff') {
      result = await doAction('staff.save', values, 'Staff member saved.');
      if (result.ok) { const r = await rpc('staff.list', {}, true); if (r.ok) staff = r.staff || []; }
    }
    if (result?.ok) modal = null;
  }

  async function copy(value) {
    if (inGame) await nuiPost('copy', { value });
    else { await navigator.clipboard.writeText(String(value || '')); toast('Copied to clipboard.'); }
  }

  async function closeMenu() {
    if (inGame) { await nuiPost('close'); visible = false; }
  }

  function handleKey(event) {
    if (event.key !== 'Escape') return;
    if (uiMode === 'report') return closeMenu();
    modal ? modal = null : selectedPlayer ? selectedPlayer = null : selectedReport ? selectedReport = null : closeMenu();
  }
  function formatDate(value) { if (!value) return 'Never'; return new Date(String(value).replace(' ', 'T') + (String(value).includes('Z') ? '' : 'Z')).toLocaleString(); }
  function formatUptime(seconds = 0) { const h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60); return h > 24 ? `${Math.floor(h / 24)}d ${h % 24}h` : `${h}h ${m}m`; }
  function formatDuration(seconds = 0) { const h = Math.floor(Number(seconds) / 3600), m = Math.floor((Number(seconds) % 3600) / 60); return h ? `${h}h ${m}m` : `${m}m`; }
  function money(value) { return new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'GBP', maximumFractionDigits: 0 }).format(Number(value) || 0); }
  function filtered(list, keys) { const q = query.trim().toLowerCase(); return !q ? list : list.filter(row => keys.some(key => String(row[key] ?? '').toLowerCase().includes(q))); }
  function chartPath(history) {
    if (!history?.length) return 'M0 88 L100 88';
    const values = history.map(h => Number(h.players) || 0), max = Math.max(...values, 1);
    return values.map((v, i) => `${i ? 'L' : 'M'} ${(i / Math.max(1, values.length - 1)) * 100} ${96 - (v / max) * 82}`).join(' ');
  }

  onMount(() => {
    if (inGame) {
      try { compactMode = localStorage.getItem('seam-admin-compact') === '1'; } catch (_) {}
    }
    if (!inGame) {
      bootstrap();
      const stream = new EventSource('/api/stream');
      stream.addEventListener('update', () => bootstrap());
      refreshTimer = setInterval(() => bootstrap(), 15000);
      return () => { stream.close(); clearInterval(refreshTimer); };
    }
    const listener = event => {
      if (event.data?.type === 'open') { uiMode = 'admin'; visible = true; bootstrap(); }
      if (event.data?.type === 'openPlayerReports') {
        uiMode = 'report';
        visible = true;
        playerReportReady = false;
        selectedPlayerReport = null;
        playerReportDetails = null;
        reportComposer = true;
        reportReply = '';
        newReport = { ...newReport, subject: '', message: String(event.data.draft || '').slice(0, 1000) };
        loadPlayerReportCenter();
      }
      if (event.data?.type === 'playerReportUpdated' && uiMode === 'report') {
        const currentId = selectedPlayerReport?.id || event.data.reportId;
        loadPlayerReportCenter(currentId, reportComposer);
      }
      if (event.data?.type === 'adminReportsChanged' && uiMode === 'admin') {
        if (page === 'reports') {
          loadPage('reports', true);
          if (selectedReport && Number(selectedReport.id) === Number(event.data.reportId)) openReport(selectedReport);
        }
      }
      if (event.data?.type === 'close') visible = false;
      if (event.data?.type === 'copy' && event.data?.value != null) {
        navigator.clipboard?.writeText(String(event.data.value)).then(() => toast('Copied to clipboard.')).catch(() => {});
      }
    };
    window.addEventListener('message', listener);
    refreshTimer = setInterval(() => {
      if (!visible) return;
      if (uiMode === 'admin' && ready) bootstrap();
      if (uiMode === 'report' && playerReportReady) loadPlayerReportCenter(selectedPlayerReport?.id, reportComposer);
    }, 15000);
    return () => { window.removeEventListener('message', listener); clearInterval(refreshTimer); };
  });

  $: filteredPlayers = filtered(players, ['source', 'name', 'characterName', 'citizenid', 'jobLabel']);
  $: filteredCharacters = filtered(characters, ['citizenid', 'accountName', 'characterName', 'phone', 'job']);
  $: filteredItems = filtered(items, ['name', 'label', 'type']);
  $: filteredVehicles = filtered(vehicles, ['model', 'name', 'brand', 'category']);
  $: filteredBans = filtered(bans, ['id', 'player_name', 'reason', 'admin_name']);
  $: filteredLogs = filtered(logs, ['id', 'action', 'admin_name', 'target_name']);
  $: filteredResources = filtered(resources, ['name', 'state']);
  $: filteredStaff = filtered(staff, ['name', 'identifierText', 'role']);
  $: primaryAccount = data.accounts?.[0] || { name: 'cash', label: 'Cash' };
  $: secondaryAccount = data.accounts?.[1] || { name: 'bank', label: 'Bank' };
  $: activePlayerReports = playerReports.filter(report => report.status !== 'closed').length;
</script>

<svelte:window on:keydown={handleKey} />

{#if visible}
  {#if inGame && uiMode === 'report'}
    <div class="player-report-overlay">
      <section class="player-report-window" aria-label="Player report centre">
        <header class="player-report-header">
          <div class="player-report-brand"><div class="brand-mark">S</div><div><span>SEAM SUPPORT</span><h1>City report centre</h1><p>Speak directly with the staff team and follow every update.</p></div></div>
          <div class="player-report-header-actions"><span class="report-availability"><i></i>Staff channel open</span><button class="icon-button close" title="Close" on:click={closeMenu}><Icon name="close" /></button></div>
        </header>

        <div class="player-report-layout">
          <div class="player-report-sidebar">
            <div class="player-report-sidebar-head"><div><span class="eyebrow">YOUR REQUESTS</span><strong>{activePlayerReports} active · {playerReports.length} total</strong></div><button class="new-report-button" title="New report" on:click={openPlayerReportComposer}><Icon name="plus" size={17}/></button></div>
            <div class="player-report-list">
              {#each playerReports as report}
                <button class:active={!reportComposer && Number(selectedPlayerReport?.id) === Number(report.id)} class="player-report-list-item" on:click={() => openPlayerReport(report)}>
                  <div><span class={`status ${report.status}`}>{report.status}</span><small>#{report.id}</small></div>
                  <strong>{report.subject || 'Support request'}</strong>
                  <p>{report.message}</p>
                  <time>{formatDate(report.updated_at || report.created_at)}</time>
                </button>
              {:else}
                <div class="player-report-empty"><Icon name="report" size={26}/><strong>No reports yet</strong><span>Your conversations with staff will stay here.</span></div>
              {/each}
            </div>
            <div class="player-report-sidebar-note"><Icon name="shield" size={16}/><span>Reports are visible only to you and authorised SeaM staff.</span></div>
          </div>

          <main class="player-report-main">
            {#if !playerReportReady}
              <div class="player-report-loading"><div class="spinner"></div><p>Opening your support channel</p></div>
            {:else if reportComposer}
              <div class="player-report-compose">
                <div class="player-report-title"><span class="eyebrow">NEW REPORT</span><h2>How can we help?</h2><p>Give staff the useful details up front so they can resolve this quickly.</p></div>
                {#if activePlayerReports >= playerReportMaxOpen}
                  <div class="report-limit-notice"><Icon name="lock" size={17}/><span>You already have {activePlayerReports} active reports. Close one before opening another.</span></div>
                {/if}
                <form on:submit|preventDefault={submitPlayerReport}>
                  <div class="player-report-field-row">
                    <label><span>Category</span><select bind:value={newReport.category} required>{#each playerReportCategories as category}<option value={category.id}>{category.label}</option>{/each}</select></label>
                    <label class="report-subject-field"><span>Subject</span><input bind:value={newReport.subject} minlength="3" maxlength="120" required placeholder="A short summary of the issue" /></label>
                  </div>
                  <label><span>What happened?</span><textarea bind:value={newReport.message} minlength="10" maxlength="1000" required placeholder="Include names, locations, what happened and anything staff should know."></textarea><small>{newReport.message.length} / 1000</small></label>
                  <div class="report-compose-footer"><div><Icon name="activity" size={16}/><span>Your report appears instantly in the admin panel.</span></div><button class="button primary" type="submit" disabled={activePlayerReports >= playerReportMaxOpen || playerReportLoading}><Icon name="send" size={17}/> Send report</button></div>
                </form>
                <div class="report-guidance"><div><b>01</b><span><strong>Be specific</strong><small>Names, player IDs and locations help staff act faster.</small></span></div><div><b>02</b><span><strong>Stay available</strong><small>Staff replies arrive here live while you are in the city.</small></span></div><div><b>03</b><span><strong>One issue per report</strong><small>Keep each conversation focused and close it when resolved.</small></span></div></div>
              </div>
            {:else if selectedPlayerReport}
              <div class="player-report-conversation">
                <div class="player-report-conversation-head">
                  <div><div class="report-meta"><span class={`status ${selectedPlayerReport.status}`}>{selectedPlayerReport.status}</span><span>REPORT #{selectedPlayerReport.id}</span><span>{reportCategoryLabel(selectedPlayerReport.category)}</span></div><h2>{selectedPlayerReport.subject || 'Support request'}</h2><p>{selectedPlayerReport.claimed_by ? `Assigned to ${selectedPlayerReport.claimed_by}` : selectedPlayerReport.status === 'open' ? 'Waiting for a staff member' : `Closed by ${selectedPlayerReport.closed_by || 'staff'}`}</p></div>
                  {#if selectedPlayerReport.status !== 'closed'}<button class="button danger-soft compact" on:click={closePlayerReport}>Close report</button>{/if}
                </div>
                <div class="player-report-status-line"><div class:complete={true}><i></i><span>Submitted</span></div><div class:complete={selectedPlayerReport.status === 'claimed' || selectedPlayerReport.status === 'closed'}><i></i><span>In review</span></div><div class:complete={selectedPlayerReport.status === 'closed'}><i></i><span>Resolved</span></div></div>
                {#if !playerReportDetails}
                  <div class="player-report-loading"><div class="spinner"></div></div>
                {:else}
                  <div class="player-report-messages">
                    {#each playerReportDetails.messages as message}
                      <div class:from-staff={message.sender_type === 'staff'} class="player-report-message"><div><strong>{message.sender_type === 'staff' ? `${message.sender_name} · Staff` : 'You'}</strong><span>{formatDate(message.created_at)}</span></div><p>{message.message}</p></div>
                    {/each}
                  </div>
                  {#if selectedPlayerReport.status !== 'closed'}
                    <form class="player-report-reply" on:submit|preventDefault={submitPlayerReportReply}><input bind:value={reportReply} maxlength="1000" required placeholder="Write a reply to staff..."/><button class="button primary" type="submit" disabled={!reportReply.trim()}><Icon name="send" size={17}/><span>Reply</span></button></form>
                  {:else}
                    <div class="player-report-closed"><Icon name="shield" size={18}/><span>This report is closed. Create a new report if you still need help.</span><button class="button secondary compact" on:click={openPlayerReportComposer}>New report</button></div>
                  {/if}
                {/if}
              </div>
            {:else}
              <div class="player-report-loading"><Icon name="report" size={28}/><p>Select a report or create a new one.</p></div>
            {/if}
          </main>
        </div>
      </section>
    </div>
  {:else}
  <div class:browser-shell={!inGame} class:ingame-shell={inGame} class:compact-mode={inGame && compactMode} class="app-shell">
    {#if !ready && !loginRequired}
      <div class="loading-screen"><div class="brand-mark large">S</div><div class="spinner"></div><p>Opening the harbormaster's ledger</p></div>
    {:else if loginRequired}
      <div class="login-screen">
        <div class="login-card">
          <div class="brand-mark large">S</div><span class="eyebrow">SEAM · COMMAND LEDGER</span>
          <h1>Take command from any shore.</h1><p>Sign in with the Discord account assigned to your staff profile.</p>
          <a class="button primary wide" href={loginUrl}><Icon name="shield" /> Continue with Discord</a>
          <span class="secure-note"><Icon name="lock" size={15} /> Access is checked against your SeaM staff role</span>
        </div>
      </div>
    {:else}
      <aside class:open={sidebarOpen}>
        <div class="brand"><div class="brand-mark">S</div><div><strong>SeaM</strong><span>HARBOUR COMMAND</span></div></div>
        <nav>
          <span class="nav-label">OVERVIEW</span>
          {#each nav as item, index}
            {#if has(item.permission)}
              {#if index === 5}<span class="nav-label spaced">MANAGEMENT</span>{/if}
              <button class:active={page === item.id} on:click={() => loadPage(item.id)}>
                <Icon name={item.icon} /><span>{item.label}</span>
                {#if item.count && item.count() > 0}<b>{item.count()}</b>{/if}
              </button>
            {/if}
          {/each}
        </nav>
        <div class="admin-card">
          <div class="avatar">{data.admin?.name?.slice(0, 1)?.toUpperCase() || 'A'}</div>
          <div><strong>{data.admin?.name}</strong><span style={`color:${data.admin?.roleColor}`}>{data.admin?.roleLabel}</span></div>
          {#if !inGame}<button title="Sign out" on:click={() => fetch('/api/logout', { method: 'POST' }).then(() => location.reload())}><Icon name="logout" size={17} /></button>{/if}
        </div>
      </aside>
      <button class="mobile-scrim" class:show={sidebarOpen} aria-label="Close navigation" on:click={() => sidebarOpen = false}></button>

      <main>
        <header>
          <div class="header-title"><button class="mobile-menu" on:click={() => sidebarOpen = true}><Icon name="menu" /></button><div><h1>{pageTitles[page]?.[0]}</h1><p>{pageTitles[page]?.[1]}</p></div></div>
          <div class="header-actions">
            {#if inGame && has('staff.duty')}<button class:active={data.admin?.onDuty} class="button duty-button" on:click={toggleDuty}><i></i>{data.admin?.onDuty ? 'ON DUTY' : 'GO ON DUTY'}</button>{/if}
            <div class="live-pill"><i></i><span>{data.server?.online || 0} ONLINE</span></div>
            <button class="icon-button" title="Refresh" on:click={() => bootstrap()} class:spin={loading}><Icon name="refresh" /></button>
            {#if inGame}<button class="icon-button close" title="Close" on:click={closeMenu}><Icon name="close" /></button>{/if}
          </div>
        </header>

        <section class="content">
          {#if page === 'dashboard'}
            <div class="metrics-grid">
              <div class="metric"><div class="metric-icon mint"><Icon name="users" /></div><div><span>PLAYERS ONLINE</span><strong>{data.server.online}<small> / {data.server.maxPlayers}</small></strong><em><i></i> Live now</em></div></div>
              <div class="metric"><div class="metric-icon blue"><Icon name="shield" /></div><div><span>STAFF ONLINE</span><strong>{data.server.staffOnline}</strong><em>{data.server.staffOnDuty || 0} currently on duty</em></div></div>
              <div class="metric"><div class="metric-icon amber"><Icon name="report" /></div><div><span>OPEN REPORTS</span><strong>{data.server.reports}</strong><em>Waiting for staff</em></div></div>
              <div class="metric"><div class="metric-icon purple"><Icon name="clock" /></div><div><span>SERVER UPTIME</span><strong>{formatUptime(data.server.uptime)}</strong><em>Current session</em></div></div>
            </div>

            <div class="dashboard-grid">
              <div class="panel chart-panel">
                <div class="panel-heading"><div><span class="eyebrow">CITY ACTIVITY</span><h2>Player count</h2></div><span class="range-pill">Last 24 hours</span></div>
                <div class="chart-wrap">
                  <div class="chart-labels"><span>{Math.max(...(data.history || []).map(h => Number(h.players) || 0), data.server.online || 1)}</span><span>0</span></div>
                  <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-label="Player count history">
                    <defs><linearGradient id="area" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a86b21" stop-opacity=".38"/><stop offset="1" stop-color="#a86b21" stop-opacity="0"/></linearGradient></defs>
                    <path class="area" d={`${chartPath(data.history)} L100 100 L0 100 Z`} /><path class="line" d={chartPath(data.history)} />
                  </svg>
                </div>
              </div>
              <div class="panel city-status">
                <div class="panel-heading"><div><span class="eyebrow">SERVER STATUS</span><h2>{data.server.name}</h2></div><span class="status-badge">HEALTHY</span></div>
                <div class="status-list"><div><span><Icon name="online" /> Capacity</span><strong>{Math.round((data.server.online / Math.max(data.server.maxPlayers, 1)) * 100)}%</strong></div><div><span><Icon name="report" /> Reports</span><strong>{data.server.reports} open</strong></div><div><span><Icon name="ban" /> Active bans</span><strong>{data.server.activeBans}</strong></div><div><span><Icon name="activity" /> Resource</span><strong>Operational</strong></div></div>
              </div>
            </div>

            {#if inGame}
              <div class="section-heading"><div><span class="eyebrow">QUICK ACCESS</span><h2>Personal controls</h2></div></div>
              {#if !data.admin?.onDuty}<div class="duty-notice"><Icon name="shield" size={17}/><span>Go on duty from the header to unlock powers, teleports, entity tools and local vehicle controls.</span></div>{/if}
              <div class:duty-locked={!data.admin?.onDuty} class="action-groups">
                <div class="action-card"><div class="action-title"><div class="metric-icon mint small"><Icon name="heart" /></div><div><h3>Essential actions</h3><p>Care and navigation</p></div></div><div class="action-buttons"><button on:click={() => doAction('self.action', { action: 'revive' })}>Revive</button><button on:click={() => doAction('self.action', { action: 'heal' })}>Heal & armour</button><button on:click={() => doAction('self.action', { action: 'marker' })}>Go to marker</button><button on:click={() => doAction('self.action', { action: 'back' })}>Go back</button><button on:click={() => openForm('coords')}>Go to coords</button></div></div>
                <div class="action-card"><div class="action-title"><div class="metric-icon purple small"><Icon name="zap" /></div><div><h3>Movement & powers</h3><p>Native SeaM staff modes</p></div></div><div class="action-buttons">{#each ['noclip','invisible','god','superjump','fastrun','stamina','ragdoll','infiniteammo'] as action}<button class:active={selfStates[action]} on:click={() => toggleSelf(action)}>{action === 'ragdoll' ? 'No ragdoll' : action === 'infiniteammo' ? 'Infinite ammo' : action === 'superjump' ? 'Super jump' : action === 'fastrun' ? 'Fast run' : action}</button>{/each}</div></div>
                <div class="action-card"><div class="action-title"><div class="metric-icon blue small"><Icon name="eye" /></div><div><h3>Display & developer tools</h3><p>Players, coordinates and entities</p></div></div><div class="action-buttons">{#each [{id:'names',label:'Player names'},{id:'blips',label:'Player blips'},{id:'radar',label:'Force radar'},{id:'coords',label:'Live coords'}] as tool}<button class:active={selfStates[tool.id]} on:click={() => toggleSelf(tool.id)}>{tool.label}</button>{/each}{#if has('self.devtools')}<button class:active={selfStates.devlaser} on:click={() => toggleSelf('devlaser')}>Entity laser</button>{/if}</div></div>
                {#if has('vehicles.manage')}<div class="action-card"><div class="action-title"><div class="metric-icon amber small"><Icon name="car" /></div><div><h3>Vehicle toolkit</h3><p>Operate the current or nearest vehicle</p></div></div><div class="action-buttons">{#each [{id:'repair',label:'Repair'},{id:'clean',label:'Clean'},{id:'flip',label:'Flip'},{id:'boost',label:'Boost'},{id:'fuel',label:'Refuel'},{id:'engine',label:'Engine'},{id:'unlock',label:'Unlock'},{id:'god',label:'Protect'},{id:'inspect',label:'Copy details'}] as action}<button on:click={() => doAction('vehicle.action', { action: action.id })}>{action.label}</button>{/each}</div></div>{/if}
                <div class="action-card"><div class="action-title"><div class="metric-icon amber small"><Icon name="location" /></div><div><h3>Teleport locations</h3><p>Common city landmarks</p></div></div><div class="action-buttons">{#each data.teleports.slice(0, 6) as point, index}<button on:click={() => doAction('self.teleportPreset', { index: index + 1 })}>{point.label}</button>{/each}</div></div>
              </div>
            {:else}
              <div class="section-heading"><div><span class="eyebrow">REMOTE CONTROL</span><h2>Common actions</h2></div></div>
              <div class="remote-actions"><button class="feature-button" on:click={() => loadPage('players')}><div class="metric-icon mint"><Icon name="users" /></div><div><strong>Manage players</strong><span>Moderation, jobs, money and inventory</span></div><Icon name="chevron" /></button><button class="feature-button" on:click={() => loadPage('reports')}><div class="metric-icon amber"><Icon name="report" /></div><div><strong>Open reports</strong><span>Respond to support requests live</span></div><Icon name="chevron" /></button>{#if has('server.announce')}<button class="feature-button" on:click={() => openForm('announcement')}><div class="metric-icon blue"><Icon name="send" /></div><div><strong>Make announcement</strong><span>Broadcast a message to the city</span></div><Icon name="chevron" /></button>{/if}</div>
            {/if}

          {:else if page === 'analytics'}
            <div class="metrics-grid">
              <div class="metric"><div class="metric-icon mint"><Icon name="users"/></div><div><span>CHARACTERS</span><strong>{analytics.totals?.characters || 0}</strong><em>SeaM Core records</em></div></div>
              <div class="metric"><div class="metric-icon blue"><Icon name="activity"/></div><div><span>ADMIN ACTIONS</span><strong>{analytics.totals?.actionsToday || 0}</strong><em>Last 24 hours</em></div></div>
              <div class="metric"><div class="metric-icon amber"><Icon name="report"/></div><div><span>REPORTS CREATED</span><strong>{analytics.totals?.reportsToday || 0}</strong><em>Last 24 hours</em></div></div>
              <div class="metric"><div class="metric-icon purple"><Icon name="clock"/></div><div><span>STAFF DUTY</span><strong>{formatDuration(analytics.totals?.dutySeconds)}</strong><em>Last 24 hours</em></div></div>
            </div>
            <div class="section-heading"><div><span class="eyebrow">ECONOMY FLOW</span><h2>Created and destroyed money</h2></div><span class="result-count">Last 24 hours</span></div>
            <div class="panel table-panel"><table><thead><tr><th>Account</th><th>Created</th><th>Destroyed</th><th>Net flow</th><th>Movements</th></tr></thead><tbody>{#each analytics.economy || [] as row}<tr><td><span class="job-pill">{row.account}</span></td><td><strong>{money(row.created)}</strong></td><td>{money(row.destroyed)}</td><td class:warning={Number(row.created) < Number(row.destroyed)}><strong>{money(Number(row.created) - Number(row.destroyed))}</strong></td><td>{row.moves}</td></tr>{:else}<tr><td colspan="5"><div class="empty">No SeaM Core ledger movement was recorded in this period.</div></td></tr>{/each}</tbody></table></div>
            <div class="analytics-grid">
              <div class="panel"><div class="panel-heading"><div><span class="eyebrow">MOST USED</span><h2>Administrative actions</h2></div><span class="range-pill">24 hours</span></div><div class="rank-list">{#each analytics.actions || [] as row, index}<div><span><b>{index + 1}</b>{row.action.replaceAll('.', ' ')}</span><strong>{row.uses}</strong></div>{:else}<div class="empty">No actions recorded.</div>{/each}</div></div>
              <div class="panel"><div class="panel-heading"><div><span class="eyebrow">OFFICER HOURS</span><h2>Duty leaderboard</h2></div><span class="range-pill">7 days</span></div><div class="rank-list">{#each analytics.duty || [] as row, index}<div><span><b>{index + 1}</b>{row.staff_name}<small>{row.role_name} · {row.sessions} sessions</small></span><strong>{formatDuration(row.seconds)}</strong></div>{:else}<div class="empty">No duty sessions recorded.</div>{/each}</div></div>
            </div>
            <div class="folio-stats"><span><b>{analytics.totals?.inventoryStacks || 0}</b> live inventory stacks</span><span><b>{Math.round((analytics.totals?.inventoryWeight || 0) / 1000)}</b> kg carried online</span><span><b>{analytics.totals?.warnings || 0}</b> warnings on record</span></div>

          {:else if page === 'players'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search name, ID, citizen ID or job" /></div><span class="result-count">{filteredPlayers.length} players</span></div>
            <div class="panel table-panel"><table><thead><tr><th>Player</th><th>Character</th><th>Job</th><th>Ping</th><th></th></tr></thead><tbody>{#each filteredPlayers as player}<tr on:dblclick={() => openPlayer(player)}><td><div class="person"><div class="avatar small-avatar">{player.name.slice(0,1).toUpperCase()}</div><div><strong>{player.name}</strong><span>ID {player.source} {player.role ? `• ${player.role}` : ''} {player.staffOnDuty ? '• ON DUTY' : ''}</span></div></div></td><td><strong>{player.characterName || 'Unknown'}</strong><span class="subtext">{player.citizenid}</span></td><td><span class="job-pill">{player.jobLabel}</span><span class="subtext">{player.grade}</span></td><td><span class:warning={player.ping > 150}>{player.ping} ms</span></td><td><button class="row-button" on:click={() => openPlayer(player)}>Manage <Icon name="chevron" size={15}/></button></td></tr>{:else}<tr><td colspan="5"><div class="empty">No players match your search.</div></td></tr>{/each}</tbody></table></div>

          {:else if page === 'characters'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search character, citizen ID, account or job" /></div><span class="result-count">{filteredCharacters.length} characters</span></div>
            <div class="panel table-panel"><table><thead><tr><th>Character</th><th>Citizen ID</th><th>Job</th><th>Money</th><th>Phone</th><th>Last updated</th></tr></thead><tbody>{#each filteredCharacters as character}<tr><td><div class="person"><div class="avatar small-avatar">{(character.characterName || '?').slice(0,1).toUpperCase()}</div><div><strong>{character.characterName || 'Unknown'}</strong><span>{character.accountName}</span></div></div></td><td><button class="plain-copy" on:click={() => copy(character.citizenid)}><code>{character.citizenid}</code><Icon name="copy" size={13}/></button></td><td><span class="job-pill">{character.job}</span><span class="subtext">{character.grade || 'Grade 0'}</span></td><td><strong>{primaryAccount.label} {money(character.accounts?.[primaryAccount.name])}</strong><span class="subtext">{secondaryAccount.label} {money(character.accounts?.[secondaryAccount.name])}</span></td><td>{character.phone || '—'}</td><td>{formatDate(character.lastUpdated)}</td></tr>{:else}<tr><td colspan="6"><div class="empty">No characters match your search.</div></td></tr>{/each}</tbody></table></div>

          {:else if page === 'reports'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search reports" /></div><label class="toggle-label"><input type="checkbox" bind:checked={includeClosed} on:change={() => loadPage('reports')} /><span></span>Show closed</label><span class="result-count">{reports.length} reports</span></div>
            <div class="reports-grid">{#each filtered(reports, ['id','reporter_name','subject','category','message','claimed_by']) as report}<button class="report-card" on:click={() => openReport(report)}><div class="report-top"><span class={`status ${report.status}`}>{report.status}</span><span>{report.category || 'general'} · #{report.id}</span></div><h3>{report.subject || 'Support request'}</h3><span class="report-author">{report.reporter_name}</span><p>{report.message}</p><footer><span>{formatDate(report.updated_at || report.created_at)}</span><span>{report.claimed_by || 'Unassigned'}</span></footer></button>{:else}<div class="panel empty">No reports found.</div>{/each}</div>

          {:else if page === 'items'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search item name or label" /></div><span class="result-count">{filteredItems.length} items</span></div>
            <div class="directory-grid">{#each filteredItems as item}<div class="directory-card"><div class="directory-icon"><Icon name="box"/></div><div><strong>{item.label}</strong><code>{item.name}</code><span>{item.weight}g • {item.type}{item.unique ? ' • Unique' : ''}</span></div>{#if has('players.giveitem')}<button on:click={() => openForm('item', { item: item.name })}>Give</button>{/if}</div>{/each}</div>

          {:else if page === 'vehicles'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search model, brand or category" /></div>{#if inGame}<button class="button primary" disabled={!data.admin?.onDuty} on:click={() => openForm('vehicle')}><Icon name="plus" size={16}/> Spawn model</button>{/if}<span class="result-count">{filteredVehicles.length} vehicles</span></div>
            {#if inGame && has('vehicles.manage')}<div class:duty-locked={!data.admin?.onDuty} class="tool-strip">{#each [{id:'repair',label:'Repair'},{id:'clean',label:'Clean'},{id:'flip',label:'Flip'},{id:'fuel',label:'Refuel'},{id:'max',label:'Max mods'},{id:'boost',label:'Boost'},{id:'engine',label:'Engine'},{id:'unlock',label:'Unlock'},{id:'god',label:'Protect'},{id:'inspect',label:'Copy details'}] as action}<button class="button secondary" on:click={() => doAction('vehicle.action',{action:action.id})}>{action.label}</button>{/each}<button class="button danger-soft" on:click={() => doAction('vehicle.action',{action:'delete'})}>Delete nearby</button></div>{/if}
            <div class="directory-grid vehicles">{#each filteredVehicles as vehicle}<div class="directory-card"><div class="directory-icon"><Icon name="car"/></div><div><strong>{vehicle.brand} {vehicle.name}</strong><code>{vehicle.model}</code><span>{vehicle.category} • {money(vehicle.price)}</span></div>{#if inGame && has('vehicles.manage')}<button disabled={!data.admin?.onDuty} on:click={() => doAction('vehicle.action', {action:'spawn', model:vehicle.model}, 'Vehicle spawned.')}>Spawn</button>{/if}</div>{/each}</div>

          {:else if page === 'bans'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search ID, player, reason or admin" /></div><span class="result-count">{filteredBans.length} bans</span></div>
            <div class="panel table-panel"><table><thead><tr><th>Ban</th><th>Player</th><th>Reason</th><th>Expires</th><th>Status</th><th></th></tr></thead><tbody>{#each filteredBans as ban}<tr><td><strong>#{ban.id}</strong><span class="subtext">{formatDate(ban.created_at)}</span></td><td><strong>{ban.player_name}</strong><span class="subtext">by {ban.admin_name}</span></td><td class="reason-cell">{ban.reason}</td><td>{ban.expires_at ? formatDate(ban.expires_at) : 'Permanent'}</td><td><span class={`status ${ban.active ? 'open' : 'closed'}`}>{ban.active ? 'Active' : 'Revoked'}</span></td><td>{#if ban.active && has('bans.manage')}<button class="button danger-soft compact" on:click={async () => { if ((await doAction('bans.revoke',{id:ban.id},'Ban revoked.')).ok) loadPage('bans'); }}>Revoke</button>{/if}</td></tr>{/each}</tbody></table></div>

          {:else if page === 'server'}
            <div class="server-grid">
              <div class="panel control-card"><div class="panel-heading"><div><span class="eyebrow">COMMUNICATION</span><h2>City announcement</h2></div><Icon name="send"/></div><p>Send a notification and chat message to every connected player.</p><button class="button primary" on:click={() => openForm('announcement')}>Write announcement</button></div>
              <div class="panel control-card"><div class="panel-heading"><div><span class="eyebrow">WORLD</span><h2>Weather & time</h2></div><Icon name="activity"/></div><div class="form-row"><select id="weather"><option>EXTRASUNNY</option><option>CLEAR</option><option>CLOUDS</option><option>OVERCAST</option><option>RAIN</option><option>THUNDER</option><option>FOGGY</option><option>SNOW</option><option>XMAS</option></select><button class="button secondary" on:click={() => doAction('server.world',{weather:document.getElementById('weather').value})}>Apply</button></div><div class="form-row"><input id="world-hour" type="number" min="0" max="23" value="12"/><input id="world-minute" type="number" min="0" max="59" value="0"/><button class="button secondary" on:click={() => doAction('server.time',{hour:document.getElementById('world-hour').value,minute:document.getElementById('world-minute').value})}>Set time</button></div></div>
              {#if inGame && has('server.cleararea')}<div class="panel control-card"><div class="panel-heading"><div><span class="eyebrow">WORLD CLEANUP</span><h2>Clear nearby entities</h2></div><Icon name="trash"/></div><p>Remove selected world entities around your current location with a capped radius.</p><button class="button danger-soft" disabled={!data.admin?.onDuty} on:click={() => openForm('clearArea')}>Configure clear area</button></div>{/if}
            </div>
            <div class="section-heading"><div><span class="eyebrow">RESOURCES</span><h2>Resource manager</h2></div></div>
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search resources" /></div><span class="result-count">{filteredResources.length} resources</span></div>
            <div class="panel table-panel"><table><thead><tr><th>Resource</th><th>State</th><th>Protection</th><th></th></tr></thead><tbody>{#each filteredResources as resource}<tr><td><strong>{resource.name}</strong></td><td><span class={`status ${resource.state === 'started' ? 'claimed' : 'closed'}`}>{resource.state}</span></td><td>{resource.protected ? 'Protected' : 'Manageable'}</td><td><div class="button-row end">{#if !resource.protected && has('server.resources')}<button class="button secondary compact" on:click={async()=>{await doAction('server.resourceAction',{resource:resource.name,action:'restart'});loadPage('server')}}>Restart</button><button class="button danger-soft compact" on:click={async()=>{await doAction('server.resourceAction',{resource:resource.name,action:resource.state==='started'?'stop':'start'});loadPage('server')}}>{resource.state==='started'?'Stop':'Start'}</button>{/if}</div></td></tr>{/each}</tbody></table></div>

          {:else if page === 'logs'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search action, admin or target" /></div><span class="result-count">{filteredLogs.length} entries</span></div>
            <div class="timeline">{#each filteredLogs as log}<div class="log-entry"><div class="timeline-dot"></div><div class="log-main"><div><strong>{log.action.replaceAll('.', ' ')}</strong><span class={`source ${log.source_type}`}>{log.source_type}</span></div><p><b>{log.admin_name}</b>{log.target_name ? ` acted on ${log.target_name}` : ''}</p><code>{typeof log.details === 'object' ? JSON.stringify(log.details) : log.details || 'No extra details'}</code></div><time>{formatDate(log.created_at)}</time></div>{/each}</div>

          {:else if page === 'staff'}
            <div class="toolbar"><div class="search"><Icon name="search" size={18}/><input bind:value={query} placeholder="Search staff, identifier or role" /></div><button class="button primary" on:click={() => openForm('staff')}><Icon name="plus" size={17}/> Add staff</button></div>
            <div class="panel table-panel"><table><thead><tr><th>Staff member</th><th>Role</th><th>Identifiers</th><th>Updated</th><th></th></tr></thead><tbody>{#each filteredStaff as member}<tr><td><div class="person"><div class="avatar small-avatar">{member.name.slice(0,1).toUpperCase()}</div><strong>{member.name}</strong></div></td><td><span class="job-pill">{member.role}</span></td><td><div class="identifier-list">{#each member.identifiers || [] as identifier}<code>{identifier}</code>{/each}</div></td><td>{formatDate(member.updated_at)}</td><td><div class="button-row end"><button class="row-icon" title="Edit" on:click={() => openForm('staff',member)}><Icon name="tool" size={16}/></button><button class="row-icon danger" title="Delete" on:click={async()=>{if(confirm(`Remove ${member.name} from staff?`) && (await doAction('staff.delete',{id:member.id},'Staff removed.')).ok) loadPage('staff')}}><Icon name="trash" size={16}/></button></div></td></tr>{/each}</tbody></table></div>
          {/if}
        </section>
      </main>

      {#if inGame}
        <button class:active={compactMode} class="compact-toggle" type="button" aria-label={compactMode ? 'Expand admin menu' : 'Compact admin menu'} aria-pressed={compactMode} title={compactMode ? 'Expand admin menu' : 'Compact admin menu'} on:click={toggleCompactMode}>
          <Icon name={compactMode ? 'maximize' : 'minimize'} size={17}/>
        </button>
      {/if}

      {#if selectedPlayer}
        <button class="drawer-scrim" aria-label="Close player" on:click={() => selectedPlayer = null}></button>
        <aside class="drawer player-drawer">
          <div class="drawer-head"><div><span class="eyebrow">PLAYER #{selectedPlayer.source}</span><h2>{selectedPlayer.name}</h2><p>{selectedPlayer.characterName}</p></div><button class="icon-button" on:click={() => selectedPlayer = null}><Icon name="close"/></button></div>
          {#if !playerDetails}<div class="drawer-loading"><div class="spinner"></div></div>{:else}
            <div class="player-summary"><div><span>Job</span><strong>{selectedPlayer.jobLabel}</strong><small>{selectedPlayer.grade}</small></div><div><span>{primaryAccount.label}</span><strong>{money(playerDetails.accounts?.[primaryAccount.name])}</strong><small>{secondaryAccount.label} {money(playerDetails.accounts?.[secondaryAccount.name])}</small></div><div><span>Status</span><strong>{playerDetails.metadata.isdead ? 'Dead' : 'Alive'}</strong><small>{selectedPlayer.ping} ms</small></div></div>
            <div class="drawer-section"><span class="eyebrow">IDENTIFIERS</span><button class="identifier" on:click={() => copy(selectedPlayer.citizenid)}><span>citizenid</span><code>{selectedPlayer.citizenid}</code><Icon name="copy" size={15}/></button>{#each selectedPlayer.identifiers || [] as identifierValue}<button class="identifier" on:click={() => copy(identifierValue)}><span>{identifierValue.split(':')[0]}</span><code>{identifierValue}</code><Icon name="copy" size={15}/></button>{/each}</div>
            <div class="drawer-section"><span class="eyebrow">QUICK ACTIONS</span><div class="drawer-actions">{#if inGame && has('players.goto')}<button disabled={!data.admin?.onDuty} on:click={() => playerAction('goto')}><Icon name="location"/>Goto</button>{/if}{#if inGame && has('players.bring')}<button disabled={!data.admin?.onDuty} on:click={() => playerAction('bring')}><Icon name="location"/>Bring</button>{/if}{#if inGame && has('players.spectate')}<button disabled={!data.admin?.onDuty} on:click={() => playerAction('spectate')}><Icon name="eye"/>Spectate</button>{/if}{#if has('players.freeze')}<button on:click={() => playerAction('freeze',{enabled:true})}><Icon name="lock"/>Freeze</button><button on:click={() => playerAction('freeze',{enabled:false})}><Icon name="lock"/>Unfreeze</button>{/if}{#if has('players.revive')}<button on:click={() => playerAction('revive')}><Icon name="heart"/>Revive</button>{/if}{#if has('players.heal')}<button on:click={() => playerAction('heal')}><Icon name="heart"/>Heal</button><button on:click={() => playerAction('feed')}><Icon name="activity"/>Feed</button>{/if}{#if has('players.cleartasks')}<button on:click={() => playerAction('clearTasks')}><Icon name="refresh"/>Clear tasks</button>{/if}{#if has('players.kill')}<button class="danger-action" on:click={() => playerAction('kill')}><Icon name="zap"/>Kill</button>{/if}{#if inGame && has('players.inventory')}<button disabled={!data.admin?.onDuty} on:click={() => playerAction('openInventory')}><Icon name="box"/>Open inventory</button>{/if}</div></div>
            <div class="drawer-section"><span class="eyebrow">MANAGEMENT</span><div class="management-list">{#if has('players.giveitem')}<button on:click={() => openForm('item',{target:selectedPlayer.source})}>Give item <Icon name="chevron"/></button>{/if}{#if has('players.setjob')}<button on:click={() => openForm('job')}>Set job <Icon name="chevron"/></button>{/if}{#if has('players.money')}<button on:click={() => openForm('money')}>Manage money <Icon name="chevron"/></button>{/if}{#if has('players.armour')}<button on:click={() => openForm('armour')}>Set armour <Icon name="chevron"/></button>{/if}{#if has('players.needs')}<button on:click={() => openForm('needs')}>Set needs <Icon name="chevron"/></button>{/if}{#if has('players.model')}<button on:click={() => openForm('model')}>Change ped model <Icon name="chevron"/></button>{/if}{#if has('players.message')}<button on:click={() => openForm('message')}>Private staff message <Icon name="chevron"/></button>{/if}{#if has('players.notes')}<button on:click={() => openForm('note')}>Add staff note <Icon name="chevron"/></button>{/if}{#if has('players.warn')}<button on:click={() => openForm('warn')}>Issue warning <Icon name="chevron"/></button>{/if}{#if has('players.kick')}<button class="danger-text" on:click={() => openForm('kick')}>Kick player <Icon name="chevron"/></button>{/if}{#if has('players.ban')}<button class="danger-text" on:click={() => openForm('ban')}>Ban player <Icon name="chevron"/></button>{/if}</div></div>
            {#if playerDetails.inventory && has('players.inventory')}<div class="drawer-section"><div class="section-row"><span class="eyebrow">LIVE INVENTORY</span><span>{Math.round((playerDetails.inventory.weight || 0) / 1000)} / {Math.round((playerDetails.inventory.maxWeight || 0) / 1000)} kg</span></div><div class="inventory-list">{#each playerDetails.inventory.items || [] as item}<div class="inventory-row"><span class="slot-number">{item.slot}</span><div><strong>{item.label || item.name}</strong><small>{item.name} · ×{item.count}</small></div><button title="Remove item" on:click={() => openForm('removeItem', item)}><Icon name="trash" size={14}/></button></div>{:else}<div class="mini-empty">This inventory is empty.</div>{/each}</div>{#if has('players.inventory.clear')}<button class="button danger-soft compact inventory-clear" on:click={async()=>{if(confirm(`Clear ${selectedPlayer.name}'s entire inventory?`)) await playerAction('clearInventory',{},'Inventory cleared.')}}>Clear entire inventory</button>{/if}</div>{/if}
            <div class="drawer-section"><div class="section-row"><span class="eyebrow">WARNINGS</span><span>{playerDetails.warnings.length}</span></div>{#each playerDetails.warnings as warning}<div class="warning-item"><p>{warning.reason}</p><span>{warning.admin_name} • {formatDate(warning.created_at)}</span>{#if has('players.warn.remove')}<button title="Remove warning" on:click={() => playerAction('removeWarning',{id:warning.id},'Warning removed.')}><Icon name="trash" size={13}/></button>{/if}</div>{:else}<div class="mini-empty">No warnings on record.</div>{/each}</div>
            <div class="drawer-section"><div class="section-row"><span class="eyebrow">STAFF NOTES</span><span>{playerDetails.notes?.length || 0}</span></div>{#each playerDetails.notes || [] as note}<div class="warning-item note-item"><p>{note.note}</p><span>{note.admin_name} • {formatDate(note.created_at)}</span>{#if has('players.notes.remove')}<button title="Delete note" on:click={() => playerAction('deleteNote',{id:note.id},'Staff note deleted.')}><Icon name="trash" size={13}/></button>{/if}</div>{:else}<div class="mini-empty">No private staff notes.</div>{/each}</div>
          {/if}
        </aside>
      {/if}

      {#if selectedReport}
        <button class="drawer-scrim" aria-label="Close report" on:click={() => selectedReport = null}></button>
        <aside class="drawer report-drawer"><div class="drawer-head"><div><span class="eyebrow">{selectedReport.category || 'general'} · REPORT #{selectedReport.id}</span><h2>{selectedReport.subject || 'Support request'}</h2><p>{selectedReport.reporter_name} · {selectedReport.status}</p></div><button class="icon-button" on:click={() => selectedReport = null}><Icon name="close"/></button></div>
          {#if !reportDetails}<div class="drawer-loading"><div class="spinner"></div></div>{:else}<div class="report-toolbar">{#if selectedReport.status === 'open'}<button class="button primary" on:click={() => reportAction('claim')}>Claim report</button>{/if}{#if inGame}<button class="button secondary" disabled={!data.admin?.onDuty} on:click={() => reportAction('goto')}>Goto</button><button class="button secondary" disabled={!data.admin?.onDuty} on:click={() => reportAction('bring')}>Bring</button>{/if}<button class="button danger-soft" on:click={() => reportAction('close')}>Close</button></div><div class="messages">{#each reportDetails.messages as message}<div class:staff-message={message.sender_type === 'staff'} class="message"><div><strong>{message.sender_name}</strong><span>{formatDate(message.created_at)}</span></div><p>{message.message}</p></div>{/each}</div><form class="reply-box" on:submit|preventDefault={(event) => { const input=event.currentTarget.querySelector('input'); reportAction('reply',{message:input.value}); input.value=''; }}><input placeholder="Write a reply..."/><button class="button primary" type="submit"><Icon name="send" size={17}/></button></form>{/if}
        </aside>
      {/if}

      {#if modal}
        <div class="modal-wrap" role="presentation" on:mousedown={(e)=>{if(e.target===e.currentTarget)modal=null}}><form class="modal" on:submit|preventDefault={submitModal}><div class="modal-head"><div><span class="eyebrow">ADMIN ACTION</span><h2>{modalTitle(modal)}</h2></div><button type="button" class="icon-button" on:click={()=>modal=null}><Icon name="close"/></button></div><div class="modal-body">
          {#if ['warn','kick','ban'].includes(modal.type)}<label>Reason<textarea bind:value={modal.values.reason} required minlength="3" placeholder="Explain why this action is being taken"></textarea></label>{/if}
          {#if modal.type === 'ban'}<label>Duration<select bind:value={modal.values.duration}>{#each data.banDurations as duration}<option value={duration.seconds}>{duration.label}</option>{/each}</select></label>{/if}
          {#if modal.type === 'item'}<label>Player ID<input type="number" bind:value={modal.values.target} required /></label><label>Item name<input bind:value={modal.values.item} required /></label><label>Amount<input type="number" min="1" max="1000" bind:value={modal.values.amount} required /></label>{/if}
          {#if modal.type === 'job'}<label>Job name<input bind:value={modal.values.job} required placeholder="police" /></label><label>Grade<input type="number" min="0" bind:value={modal.values.grade} required /></label>{/if}
          {#if modal.type === 'money'}<label>Operation<select bind:value={modal.values.operation}><option value="add">Add</option><option value="remove">Remove</option></select></label><label>Account<select bind:value={modal.values.account}>{#each data.accounts || [] as account}<option value={account.name}>{account.label}</option>{/each}</select></label><label>Amount<input type="number" min="1" bind:value={modal.values.amount} required /></label>{/if}
          {#if modal.type === 'note'}<label>Private staff note<textarea bind:value={modal.values.note} required minlength="3" maxlength="1000" placeholder="Context future staff should know"></textarea></label>{/if}
          {#if modal.type === 'armour'}<label>Armour amount<input type="number" min="0" max="100" bind:value={modal.values.amount} required /></label>{/if}
          {#if modal.type === 'needs'}<label>Hunger<input type="number" min="0" max="100" bind:value={modal.values.hunger} required /></label><label>Thirst<input type="number" min="0" max="100" bind:value={modal.values.thirst} required /></label><label>Stress<input type="number" min="0" max="100" bind:value={modal.values.stress} required /></label>{/if}
          {#if modal.type === 'model'}<label>Pedestrian model<input bind:value={modal.values.model} required placeholder="e.g. s_m_y_cop_01" /></label>{/if}
          {#if modal.type === 'message'}<label>Message<textarea bind:value={modal.values.message} required maxlength="500" placeholder="Message shown privately to this player"></textarea></label>{/if}
          {#if modal.type === 'removeItem'}<label>Item<input bind:value={modal.values.item} required readonly /></label><label>Slot<input type="number" bind:value={modal.values.slot} readonly /></label><label>Amount<input type="number" min="1" max={modal.context.count || 1000} bind:value={modal.values.amount} required /></label>{/if}
          {#if modal.type === 'announcement'}<label>Message<textarea bind:value={modal.values.message} required minlength="3" placeholder="Write the city announcement"></textarea></label>{/if}
          {#if modal.type === 'vehicle'}<label>GTA model name<input bind:value={modal.values.model} required placeholder="e.g. sultan" /></label>{/if}
          {#if modal.type === 'coords'}<label>X<input type="number" step="any" bind:value={modal.values.x} required /></label><label>Y<input type="number" step="any" bind:value={modal.values.y} required /></label><label>Z<input type="number" step="any" bind:value={modal.values.z} required /></label><label>Heading (optional)<input type="number" step="any" bind:value={modal.values.w} /></label>{/if}
          {#if modal.type === 'clearArea'}<label>Entity type<select bind:value={modal.values.entityType}><option value="all">All world entities</option><option value="vehicles">Vehicles</option><option value="peds">Non-player peds</option><option value="objects">Objects</option></select></label><label>Radius (metres)<input type="number" min="5" max="100" bind:value={modal.values.radius} required /></label>{/if}
          {#if modal.type === 'staff'}<label>Display name<input bind:value={modal.values.name} required /></label><label>Role<select bind:value={modal.values.role}>{#each data.roles as role}<option value={role.name}>{role.label}</option>{/each}</select></label><label>Discord ID<input bind:value={modal.values.discordId} placeholder="123456789... (web access)" /></label><label>FiveM ID<input bind:value={modal.values.fivem} placeholder="fivem:1234567" /></label><label>License<input bind:value={modal.values.license} placeholder="license:..." /></label><label>License 2<input bind:value={modal.values.license2} placeholder="license2:..." /></label><label>Steam<input bind:value={modal.values.steam} placeholder="steam:110000..." /></label><label>XBL<input bind:value={modal.values.xbl} placeholder="xbl:..." /></label><label>Live<input bind:value={modal.values.live} placeholder="live:..." /></label>{/if}
        </div><div class="modal-footer"><button type="button" class="button secondary" on:click={()=>modal=null}>Cancel</button><button type="submit" class:danger={['kick','ban'].includes(modal.type)} class="button primary">Confirm action</button></div></form></div>
      {/if}
    {/if}
  </div>
  {/if}
{/if}

<div class="toast-stack">{#each toasts as item (item.id)}<div class={`toast ${item.type}`}><i></i><span>{item.message}</span></div>{/each}</div>
