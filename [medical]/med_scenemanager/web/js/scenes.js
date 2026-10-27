// Scene Manager web console: browse the scene files, spawn a scene, watch / remove live ones.
// Login + admin level are checked by med_scenemanager (server/web.lua).
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const api = OSA.api();
    const esc = OSA.esc;
    const SHOW_MAX = 300;

    const S = { token: null, scenes: [], live: [], auto: false, timer: null, busy: new Set() };

    const call = (fn, ...args) => api.call(fn, S.token, ...args);

    async function act(fn, ...args) {
        try {
            const r = await call(fn, ...args);
            if (r && r.error === 'unauthorized') { location.reload(); return null; }
            if (!r || r.ok === false) { OSA.toast((r && r.error) || 'Request failed'); return null; }
            return r;
        } catch (e) {
            OSA.toast('Server unreachable: ' + e.message);
            return null;
        }
    }

    /* ---------------------------------------------------------------- login */

    $('user').focus();
    $('loginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('user').value.trim(), pass = $('pass').value;
        if (!user || !pass) return;
        $('loginBtn').disabled = true;
        $('loginError').textContent = '';
        try {
            const r = await api.call('msmWebLogin', null, user, pass);
            if (r && r.ok) {
                S.token = r.token;
                $('pass').value = '';
                $('who').textContent = r.account;
                document.body.classList.remove('locked');
                $('login').style.display = 'none';
                start();
            } else {
                $('loginError').textContent = (r && r.error) || 'Login failed.';
                $('pass').select();
            }
        } catch (err) {
            $('loginError').textContent = 'Server unreachable: ' + err.message;
        }
        $('loginBtn').disabled = false;
    });

    $('logout').addEventListener('click', async () => {
        try { await call('msmWebLogout'); } catch (e) { /* ignore */ }
        location.reload();
    });

    /* ---------------------------------------------------------------- catalog */

    function fillSelect(el, allLabel, values) {
        const keep = el.value;
        el.innerHTML = `<option value="">${allLabel}</option>` +
            values.map(v => `<option value="${esc(v)}">${esc(v)}</option>`).join('');
        el.value = values.includes(keep) ? keep : '';
    }

    async function loadScenes() {
        const r = await act('msmWebScenes');
        if (!r) return;
        S.scenes = OSA.arr(r.scenes).map(a => ({
            name: a[0], location: a[1], category: a[2] || 'uncategorized', title: a[3], priority: a[4],
            peds: a[5], vehicles: a[6], enabled: a[7], interior: a[8],
        }));
        const uniq = key => [...new Set(S.scenes.map(s => s[key]).filter(Boolean))].sort((a, b) => a.localeCompare(b));
        fillSelect($('location'), 'All places', uniq('location'));
        fillSelect($('category'), 'All categories', uniq('category'));
        renderCatalog();
    }

    function renderCatalog() {
        const q = $('search').value.trim().toLowerCase();
        const loc = $('location').value, cat = $('category').value;
        const active = new Set(S.live.map(s => s.name));
        const hits = S.scenes.filter(s =>
            (!loc || s.location === loc) && (!cat || s.category === cat) &&
            (!q || (s.name + ' ' + s.title + ' ' + s.location).toLowerCase().includes(q)));
        const shown = hits.slice(0, SHOW_MAX);
        $('count').textContent = hits.length + ' scene(s)' +
            (hits.length > SHOW_MAX ? ' - showing the first ' + SHOW_MAX + ', narrow the search' : '');
        $('catalog').innerHTML = shown.map(s => {
            const on = active.has(s.name);
            return `<div class="sm-row${s.enabled ? '' : ' off'}${on ? ' active' : ''}">
                <div class="main">
                    <div class="name">${esc(s.name)}</div>
                    <div class="sub">${esc(s.title)}${s.interior ? ' (interior)' : ''}</div>
                </div>
                <div class="meta">${esc(s.location)}${s.category ? ' / ' + esc(s.category) : ''}<br>P${s.priority} - ${s.peds} ped, ${s.vehicles} veh</div>
                <button class="osa-btn small primary" data-spawn="${esc(s.name)}"${on || S.busy.has(s.name) ? ' disabled' : ''}>${on ? 'Active' : 'Spawn'}</button>
            </div>`;
        }).join('') || '<div class="osa-empty">No scene matches.</div>';
    }

    ['search', 'location', 'category'].forEach(id => $(id).addEventListener('input', renderCatalog));

    $('catalog').addEventListener('click', async e => {
        const btn = e.target.closest('[data-spawn]');
        if (!btn) return;
        const name = btn.dataset.spawn;
        S.busy.add(name);
        renderCatalog();
        const r = await act('msmWebSpawn', name);
        S.busy.delete(name);
        if (r) OSA.toast('Spawned ' + name + (r.warning ? ' (' + r.warning + ')' : ''), true);
        await refresh();
    });

    /* ---------------------------------------------------------------- live */

    const mmss = sec => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
    const STATUS = { unassigned: 'Not assigned', prioritized: 'Prioritized', assigned: 'Assigned', closed: 'Closed' };

    function renderLive() {
        $('clearAll').disabled = !S.live.length;
        $('live').innerHTML = S.live.map(s => `<div class="sm-card">
            <div class="head">
                <div><strong>#${s.id} ${esc(s.name)}</strong><div class="sub osa-muted">${esc(s.title)}</div></div>
                <button class="osa-btn small danger" data-remove="${s.id}">Remove</button>
            </div>
            <div class="tags">
                <span class="osa-pill ${s.closed ? '' : 'warn'}">${s.closed ? 'Task closed' : esc(STATUS[s.taskStatus] || 'No task')}</span>
                ${s.units ? `<span class="osa-pill info">${s.units} unit(s)</span>` : ''}
                <span class="osa-pill">${s.patients} patient(s)</span>
                <span class="osa-pill">${mmss(s.ageSec)}</span>
                <span class="osa-pill">${esc(s.source)}</span>
            </div>
        </div>`).join('') || '<div class="osa-empty">No active scene.</div>';
    }

    $('live').addEventListener('click', async e => {
        const btn = e.target.closest('[data-remove]');
        if (!btn) return;
        if (await act('msmWebRemove', Number(btn.dataset.remove))) await refresh();
    });

    $('clearAll').addEventListener('click', async () => {
        if (!confirm('Remove all active scenes?')) return;
        if (await act('msmWebRemove', 'all')) await refresh();
    });

    $('autoBtn').addEventListener('click', async () => {
        if (await act('msmWebAuto', !S.auto)) await refresh();
    });

    /* ---------------------------------------------------------------- polling */

    async function refresh() {
        let r;
        try { r = await call('msmWebState'); } catch (e) { $('conn').className = 'osa-conn bad'; return; }
        if (!r || r.ok === false) {
            if (r && r.error === 'unauthorized') location.reload();
            $('conn').className = 'osa-conn bad';
            return;
        }
        $('conn').className = 'osa-conn ok';
        S.live = OSA.arr(r.scenes);
        S.auto = !!r.auto;
        $('stats').textContent = r.erm ? `${S.live.length} active - ${r.free} free unit(s)` : 'med_erm is not running';
        $('autoBtn').textContent = 'Auto generator: ' + (S.auto ? 'ON' : 'OFF');
        $('autoBtn').classList.toggle('on', S.auto);
        renderLive();
        renderCatalog();
    }

    async function start() {
        await loadScenes();
        await refresh();
        S.timer = setInterval(refresh, 3000);
    }
})();
