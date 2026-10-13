// ERM Admin (web): the /ermadmin panel - shift and task history, details, auto dispatch switch.
// Sign-in with the game account, admin level checked by the server (server/webadmin.lua).
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const { esc, arr } = ERM;
    const api = OSA.api();

    const STATUS_COLOR = { available: '#2ea043', enroute: '#da3633', onscene: '#3884f4', handover: '#e6be28' };
    const TASK_COLOR = { unassigned: '#e5484d', prioritized: '#ffc53d', assigned: '#2ea043', closed: '#6e7682' };
    const TASK_LABEL = { unassigned: 'Not assigned', prioritized: 'Prioritized', assigned: 'Assigned', closed: 'Closed' };
    const PRIO_COLOR = { 1: '#e5484d', 2: '#f76b15', 3: '#ffc53d', 4: '#3e9bff' };

    const FILTERS = {
        shifts: [['all', 'All'], ['active', 'On duty'], ['ended', 'Ended']],
        tasks: [['all', 'All'], ['open', 'Open'], ['closed', 'Closed']],
    };
    const PLACEHOLDER = {
        shifts: 'Search callsign, crew, plate, type...',
        tasks: 'Search id, title, zone, caller, unit...',
    };

    const A = {
        token: null,
        tab: 'shifts',
        lists: {
            shifts: { page: 1, search: '', filter: 'all', data: null },
            tasks: { page: 1, search: '', filter: 'all', data: null },
        },
        detail: null,      // { kind: 'shift'|'task', id, data }
        history: [],
        auto: null,
        timer: null,
    };

    const call = (fn, ...args) => api.call(fn, A.token, ...args);
    const shortDate = s => (s ? String(s).slice(5, 16) : '-');
    const val = v => (v === '' || v === undefined || v === null ? '-' : esc(v));
    const prio = p => `<span class="osa-badge${p ? ' p' + p : ''}">${p ? 'P' + p : '--'}</span>`;
    const pill = (text, color) => `<span class="pill" style="color:${color}">${esc(text)}</span>`;

    function duration(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        const p = n => String(n).padStart(2, '0');
        return sec >= 3600
            ? `${Math.floor(sec / 3600)}:${p(Math.floor(sec % 3600 / 60))}:${p(sec % 60)}`
            : `${p(Math.floor(sec / 60))}:${p(sec % 60)}`;
    }

    /* ============================================================ login */

    function loginError(t) { $('adminLoginError').textContent = t || ''; }

    function leave() {
        A.token = null;
        clearTimeout(A.timer);
        location.reload();
    }

    $('adminLoginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('adminUser').value.trim(), pass = $('adminPass').value;
        if (!user || !pass) return;
        $('adminLoginBtn').disabled = true;
        loginError('');
        try {
            const r = await api.call('ermAdminLogin', null, user, pass);
            if (r && r.ok) {
                A.token = r.token;
                $('adminPass').value = '';
                $('adWho').textContent = r.account;
                document.body.classList.remove('locked');
                setTab('shifts', true);
                refreshAuto();
                A.timer = setInterval(refreshAuto, 5000);
            } else {
                loginError((r && r.error) || 'Login failed.');
                $('adminPass').select();
            }
        } catch (err) {
            loginError('Server unreachable: ' + err.message);
        }
        $('adminLoginBtn').disabled = false;
    });

    $('adLogout').addEventListener('click', async () => {
        try { await call('ermAdminLogout'); } catch (e) { /* ignore */ }
        leave();
    });

    // -> data of the query, null on failure (denied sessions go back to the login)
    async function query(kind, params) {
        try {
            const r = await call('ermAdminQuery', kind, params);
            $('adConn').className = 'osa-conn ok';
            if (r && r.error === 'unauthorized') { leave(); return null; }
            if (!r || r.ok === false) { ERM.toast((r && r.error) || 'Request failed'); return null; }
            return r.data;
        } catch (e) {
            $('adConn').className = 'osa-conn bad';
            ERM.toast('Server unreachable: ' + e.message);
            return null;
        }
    }

    /* ============================================================ auto dispatch */

    function renderAuto() {
        const b = $('adAuto'), a = A.auto;
        b.classList.toggle('on', !!(a && a.enabled));
        b.disabled = !a || !a.available || a.pending;
        b.textContent = !a ? 'Auto dispatch'
            : !a.available ? 'Auto dispatch: n/a'
            : a.enabled ? 'Auto dispatch: ON' : 'Auto dispatch: OFF';
    }

    async function refreshAuto() {
        if (!A.token) return;
        try {
            const r = await call('ermAdminAuto');
            if (r && r.error === 'unauthorized') return leave();
            if (r && r.ok) { A.auto = { available: r.available, enabled: r.enabled }; renderAuto(); }
        } catch (e) { /* next tick */ }
    }

    $('adAuto').addEventListener('click', async () => {
        if (!A.auto || !A.auto.available || A.auto.pending) return;
        A.auto.pending = true;
        renderAuto();
        try {
            const r = await call('ermAdminAutoSet', !A.auto.enabled);
            if (r && r.error === 'unauthorized') return leave();
            if (r && r.ok) A.auto = { available: r.available, enabled: r.enabled };
            else { ERM.toast((r && r.error) || 'Failed'); A.auto.pending = false; }
        } catch (e) {
            ERM.toast('Server unreachable: ' + e.message);
            A.auto.pending = false;
        }
        renderAuto();
    });

    /* ============================================================ lists */

    function setTab(tab, force) {
        if (A.tab === tab && !force) return;
        A.tab = tab;
        document.querySelectorAll('#adNav .osa-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
        $('adSearch').placeholder = PLACEHOLDER[tab];
        $('adSearch').value = A.lists[tab].search;
        $('adFilter').innerHTML = FILTERS[tab].map(f => `<option value="${f[0]}">${f[1]}</option>`).join('');
        $('adFilter').value = A.lists[tab].filter;
        if (!A.lists[tab].data || force) loadList(tab); else renderList();
    }

    document.querySelectorAll('#adNav .osa-tab').forEach(b => b.addEventListener('click', () => setTab(b.dataset.tab)));

    async function loadList(tab) {
        const l = A.lists[tab];
        const data = await query(tab, { page: l.page, search: l.search, filter: l.filter });
        if (!data) return;
        l.data = data;
        l.page = data.page || l.page;
        if (A.tab === tab) renderList();
    }

    let searchTimer = null;
    $('adSearch').addEventListener('input', () => {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => {
            const l = A.lists[A.tab];
            l.search = $('adSearch').value.trim();
            l.page = 1;
            loadList(A.tab);
        }, 300);
    });
    $('adFilter').addEventListener('change', () => {
        const l = A.lists[A.tab];
        l.filter = $('adFilter').value;
        l.page = 1;
        loadList(A.tab);
    });
    $('adPrev').addEventListener('click', () => { const l = A.lists[A.tab]; l.page--; loadList(A.tab); });
    $('adNext').addEventListener('click', () => { const l = A.lists[A.tab]; l.page++; loadList(A.tab); });

    function shiftStatus(r) {
        if (r.live) return pill(ERM.STATUS[r.live] || r.live, STATUS_COLOR[r.live] || '#2ea043');
        return r.endedAt === '' ? pill('Open', '#787878') : pill('Ended', '#6e7682');
    }

    function renderList() {
        const tab = A.tab, l = A.lists[tab], d = l.data;
        const selKind = tab === 'shifts' ? 'shift' : 'task';
        let html;
        if (!d) {
            html = '<div class="osa-empty">Loading...</div>';
        } else if (!arr(d.list).length) {
            html = '<div class="osa-empty">No results.</div>';
        } else if (tab === 'shifts') {
            html = '<table><thead><tr><th>#</th><th>Unit</th><th>Started</th><th>Duration</th><th>Crew</th><th>Tasks</th><th>Status</th></tr></thead><tbody>'
                + arr(d.list).map(r => `<tr data-id="${r.id}"${isSel(selKind, r.id) ? ' class="sel"' : ''}>
                    <td>#${r.id}</td><td><b>${esc(r.callsign)}</b> <small class="osa-muted">${esc(r.type)}</small></td>
                    <td>${shortDate(r.startedAt)}</td><td>${duration(r.duration)}</td>
                    <td>${arr(r.members).length}</td><td>${r.tasks}</td><td>${shiftStatus(r)}</td></tr>`).join('')
                + '</tbody></table>';
        } else {
            html = '<table><thead><tr><th>#</th><th>P</th><th>Title</th><th>Status</th><th>Zone</th><th>Created</th></tr></thead><tbody>'
                + arr(d.list).map(r => `<tr data-id="${r.id}"${isSel(selKind, r.id) ? ' class="sel"' : ''}>
                    <td>#${r.id}</td><td>${prio(r.priority)}</td><td title="${esc(r.title)}">${esc(r.title)}</td>
                    <td>${pill(TASK_LABEL[r.status] || r.status, TASK_COLOR[r.status] || '#6e7682')}</td>
                    <td>${esc(r.zone)}</td><td>${shortDate(r.createdAt)}</td></tr>`).join('')
                + '</tbody></table>';
        }
        $('adTable').innerHTML = html;
        $('adTable').querySelectorAll('tbody tr').forEach(tr =>
            tr.addEventListener('click', () => { A.history = []; openDetail(selKind, Number(tr.dataset.id), false); }));

        const page = d ? d.page : 1, pages = d ? d.pages : 1;
        $('adPageInfo').textContent = `Page ${page} / ${pages} - ${d ? d.total : 0} results`;
        $('adPrev').disabled = page <= 1;
        $('adNext').disabled = page >= pages;
    }

    const isSel = (kind, id) => A.detail && A.detail.kind === kind && A.detail.id === id;

    /* ============================================================ details */

    async function openDetail(kind, id, push) {
        if (push !== false && A.detail && !(A.detail.kind === kind && A.detail.id === id)) {
            A.history.push({ kind: A.detail.kind, id: A.detail.id });
        }
        A.detail = { kind, id, data: null };
        renderDetail();
        renderList();
        const data = await query(kind, { id });
        if (!data || !A.detail || A.detail.kind !== kind || A.detail.id !== id) return;
        A.detail.data = data;
        renderDetail();
    }

    $('adBack').addEventListener('click', () => {
        const prev = A.history.pop();
        if (prev) openDetail(prev.kind, prev.id, false);
    });

    const kv = pairs => '<div class="ad-kv">' + pairs.map(p =>
        `<div><label>${esc(p[0])}</label><span>${val(p[1])}</span></div>`).join('') + '</div>';
    const section = t => `<div class="ad-sec">${esc(t)}</div>`;
    const note = t => `<div class="osa-muted">${esc(t)}</div>`;

    function renderDetail() {
        const det = A.detail, body = $('adDetail');
        $('adBack').hidden = !A.history.length;
        $('adDetailKind').textContent = det ? (det.kind === 'shift' ? 'Shift details' : 'Task details') : '';
        if (!det) { body.innerHTML = '<div class="osa-empty">Select a shift or task to see its details.</div>'; return; }
        if (!det.data) { body.innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
        if (det.data.error) { body.innerHTML = `<div class="osa-empty">${esc(det.data.error)}</div>`; return; }
        body.innerHTML = det.kind === 'shift' ? shiftHtml(det.data) : taskHtml(det.data);
        body.scrollTop = 0;
        body.querySelectorAll('[data-open]').forEach(b =>
            b.addEventListener('click', () => { const [k, id] = b.dataset.open.split(':'); openDetail(k, Number(id)); }));
    }

    function shiftHtml(d) {
        const live = d.live;
        const state = live ? pill('On duty - ' + (ERM.STATUS[live.status] || live.status), STATUS_COLOR[live.status] || '#2ea043')
            : pill('Ended', '#6e7682');
        const members = arr(d.members), tasks = arr(d.tasks);
        let html = `<div class="ad-h"><h2>${esc(d.callsign)} &middot; ${esc(d.type)}</h2>${state}</div>
            <div class="ad-sub">Shift #${d.id} &middot; plate ${esc(d.plate || '-')}</div>`
            + kv([
                ['Started', d.startedAt],
                ['Ended', d.endedAt !== '' ? d.endedAt : (live ? 'Still on duty' : '-')],
                ['Duration', duration(d.duration)],
                ['Closed tasks', String(d.closed)],
                ...(live && live.task > 0 ? [['Current task', '#' + live.task]] : []),
            ]);
        html += section(`Crew (${members.length})`)
            + (members.length ? members.map(m => `<div class="ad-row">${esc(m)}</div>`).join('') : note('No members recorded.'));
        html += section(`Tasks in this shift (${tasks.length})`);
        html += tasks.length ? tasks.map(t => `<button class="ad-link" data-open="task:${t.id}">
            ${prio(t.priority)} <b>#${t.id}</b> ${esc(t.title)}
            <small>${shortDate(t.assignedAt)} &rarr; ${t.releasedAt ? shortDate(t.releasedAt) : 'now'} &middot; ${esc(t.outcome || '-')} &middot; ${esc(TASK_LABEL[t.status] || t.status)}</small></button>`).join('')
            : note('The unit did not work on any task.');
        return html;
    }

    function taskHtml(d) {
        const links = arr(d.links), log = arr(d.responseLog), unitLog = arr(d.unitLog);
        let html = `<div class="ad-h">${prio(d.priority)}<h2>#${d.id} &nbsp;${esc(d.title)}</h2>
            ${pill(TASK_LABEL[d.status] || d.status, TASK_COLOR[d.status] || '#6e7682')}</div>
            <div class="ad-sub">${esc(d.zone)}</div>`
            + kv([
                ['Caller', d.caller],
                ['Source', d.source || 'Web dispatcher'],
                ['Position', `${Number(d.x).toFixed(1)}, ${Number(d.y).toFixed(1)}, ${Number(d.z).toFixed(1)}`],
                ['Priority', d.priority > 0 ? 'P' + d.priority : 'Not set'],
            ]);
        html += section('Timeline') + kv([
            ['Created', d.createdAt], ['Prioritized', d.prioritizedAt],
            ['First assigned', d.assignedAt], ['Closed', d.closedAt],
            ...(d.closeReason ? [['Close reason', d.closeReason]] : []),
        ]);
        html += section('Description')
            + (d.description ? `<div class="ad-pre" style="color:var(--text)">${esc(d.description)}</div>` : note('No description.'));
        html += section(`Units (${links.length})`);
        if (links.length) {
            html += links.map(l => `<button class="ad-link" data-open="shift:${l.shift}">
                <b>${esc(l.callsign)}</b>${l.type ? ' &middot; ' + esc(l.type) : ''}
                <small>Shift #${l.shift} &middot; ${shortDate(l.assignedAt)} &rarr; ${l.releasedAt ? shortDate(l.releasedAt) : 'now'} &middot; ${esc(l.outcome || '-')}</small></button>`).join('');
        } else {
            html += unitLog.length ? `<div class="ad-pre">${esc(unitLog.join(', '))}</div>` : note('No unit was assigned.');
        }
        html += section(`Lights & siren (total ${duration(d.responseTotal)})`);
        html += log.length ? log.map(e => `<div class="ad-row"><b>${esc(e.unit)}</b>
            <span class="grow osa-muted">${shortDate(e.start)} &rarr; ${e.stop ? shortDate(e.stop) : 'active'}</span>
            <b style="color:${STATUS_COLOR.enroute}">${duration(e.duration)}</b></div>`).join('') : note('Not used.');
        if (d.meta) html += section('Meta (automation data)') + `<div class="ad-pre">${esc(d.meta)}</div>`;
        return html;
    }
})();
