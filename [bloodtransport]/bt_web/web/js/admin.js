// Admin (web): the /btadmin panel - shift and task history, details. Sign-in with the game account,
// the admin level is checked by the server on every call (server/webadmin.lua).
(function () {
    'use strict';

    const { $, esc, arr, api } = BT;

    const FILTERS = {
        shifts: [['all', 'All'], ['active', 'On duty'], ['ended', 'Ended']],
        tasks: [['all', 'All'], ['open', 'Open'], ['closed', 'Closed']],
    };
    const PLACEHOLDER = { shifts: 'Search unit, driver, account...', tasks: 'Search task id, product, institution, unit, driver...' };
    const REASON = { off: 'ended by the player', duty_end: 'duty ended', vehicle_lost: 'vehicle lost', died: 'died', quit: 'left the server', restart: 'server restart' };

    const A = {
        token: null, tab: 'shifts',
        lists: { shifts: { page: 1, search: '', filter: 'all', data: null }, tasks: { page: 1, search: '', filter: 'all', data: null } },
        detail: null, history: [],
    };

    const call = (fn, ...args) => api.call(fn, A.token, ...args);
    const shortDate = s => (s ? String(s).slice(5, 16) : '-');
    const val = v => (v === '' || v === undefined || v === null ? '-' : esc(v));
    const pill = (text, color) => `<span class="pill" style="color:${color}">${esc(text)}</span>`;
    const money = n => '€' + Number(n || 0).toLocaleString('en-US');
    const status = s => pill(BT.STATUS[s] || s, BT.STATUS_COLOR[s] || '#6e7682');

    /* ============================================================ login */
    function loginError(t) { $('adLoginError').textContent = t || ''; }

    function leave() {
        A.token = null;
        $('adApp').hidden = true;
        $('adLogin').hidden = false;
        $('adWho').textContent = '';
        $('adLogout').hidden = true;
        A.detail = null; A.history = [];
    }

    $('adLoginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('adUser').value.trim(), pass = $('adPass').value;
        if (!user || !pass) return;
        $('adLoginBtn').disabled = true;
        loginError('');
        try {
            const r = await api.call('btAdminLogin', null, user, pass);
            if (r && r.ok) {
                A.token = r.token;
                $('adPass').value = '';
                $('adWho').textContent = r.account;
                $('adLogout').hidden = false;
                $('adLogin').hidden = true;
                $('adApp').hidden = false;
                setTab('shifts', true);
            } else {
                loginError((r && r.error) || 'Login failed.');
                $('adPass').select();
            }
        } catch (err) {
            loginError('Server unreachable: ' + err.message);
        }
        $('adLoginBtn').disabled = false;
    });

    $('adLogout').addEventListener('click', async () => {
        try { await call('btAdminLogout'); } catch (e) { /* ignore */ }
        leave();
    });

    async function query(kind, params) {
        try {
            const r = await call('btAdminQuery', kind, params);
            if (r && r.error === 'unauthorized') { leave(); return null; }
            if (!r || r.ok === false) { OSA.toast((r && r.error) || 'Request failed'); return null; }
            return r.data;
        } catch (e) {
            OSA.toast('Server unreachable: ' + e.message);
            return null;
        }
    }

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
        searchTimer = setTimeout(() => { const l = A.lists[A.tab]; l.search = $('adSearch').value.trim(); l.page = 1; loadList(A.tab); }, 300);
    });
    $('adFilter').addEventListener('change', () => { const l = A.lists[A.tab]; l.filter = $('adFilter').value; l.page = 1; loadList(A.tab); });
    $('adPrev').addEventListener('click', () => { const l = A.lists[A.tab]; l.page--; loadList(A.tab); });
    $('adNext').addEventListener('click', () => { const l = A.lists[A.tab]; l.page++; loadList(A.tab); });

    const isSel = (kind, id) => A.detail && A.detail.kind === kind && A.detail.id === id;

    function renderList() {
        const tab = A.tab, l = A.lists[tab], d = l.data;
        const selKind = tab === 'shifts' ? 'shift' : 'task';
        let html;
        if (!d) html = '<div class="osa-empty">Loading...</div>';
        else if (!arr(d.list).length) html = '<div class="osa-empty">No results.</div>';
        else if (tab === 'shifts') {
            html = '<table><thead><tr><th>#</th><th>Unit</th><th>Driver</th><th>Started</th><th>Duration</th><th>Delivered</th><th>Tasks</th><th>Status</th></tr></thead><tbody>'
                + arr(d.list).map(r => `<tr data-id="${r.id}"${isSel(selKind, r.id) ? ' class="sel"' : ''}>
                    <td>#${r.id}</td><td><b>${esc(r.unit)}</b></td><td>${esc(BT.clean(r.player))}</td><td>${shortDate(r.startedAt)}</td>
                    <td>${BT.duration(r.duration)}</td><td>${r.delivered}</td><td>${r.tasks}</td>
                    <td>${r.live ? pill('On duty', '#2ea043') : pill('Ended', '#6e7682')}</td></tr>`).join('') + '</tbody></table>';
        } else {
            html = '<table><thead><tr><th>#</th><th>Cargo</th><th>From &rarr; To</th><th>Unit</th><th>Created</th><th>Status</th></tr></thead><tbody>'
                + arr(d.list).map(r => `<tr data-id="${r.id}"${isSel(selKind, r.id) ? ' class="sel"' : ''}>
                    <td>T-${r.id}</td><td>${esc(BT.what(r))}</td><td title="${esc(r.fromName + ' -> ' + r.toName)}">${esc(r.fromName)} &rarr; ${esc(r.toName)}</td>
                    <td>${val(r.unit)}</td><td>${shortDate(r.createdAt)}</td><td>${status(r.status)}</td></tr>`).join('') + '</tbody></table>';
        }
        $('adTable').innerHTML = html;
        $('adTable').querySelectorAll('tbody tr').forEach(tr =>
            tr.addEventListener('click', () => { A.history = []; openDetail(selKind, Number(tr.dataset.id), false); }));
        const page = d ? d.page : 1, pages = d ? d.pages : 1;
        $('adPageInfo').textContent = `Page ${page} / ${pages} - ${d ? d.total : 0} results`;
        $('adPrev').disabled = page <= 1;
        $('adNext').disabled = page >= pages;
    }

    /* ============================================================ details */
    async function openDetail(kind, id, push) {
        if (push !== false && A.detail && !(A.detail.kind === kind && A.detail.id === id)) A.history.push({ kind: A.detail.kind, id: A.detail.id });
        A.detail = { kind, id, data: null };
        renderDetail(); renderList();
        const data = await query(kind, { id });
        if (!data || !A.detail || A.detail.kind !== kind || A.detail.id !== id) return;
        A.detail.data = data;
        renderDetail();
    }

    $('adBack').addEventListener('click', () => { const prev = A.history.pop(); if (prev) openDetail(prev.kind, prev.id, false); });

    const kv = pairs => '<div class="ad-kv">' + pairs.map(p => `<div><label>${esc(p[0])}</label><span>${val(p[1])}</span></div>`).join('') + '</div>';
    const section = t => `<div class="ad-sec">${esc(t)}</div>`;
    const note = t => `<div class="osa-muted">${esc(t)}</div>`;

    function renderDetail() {
        const det = A.detail, body = $('adDetail');
        $('adBack').hidden = !A.history.length;
        $('adDetailKind').textContent = det ? (det.kind === 'shift' ? 'Shift details' : 'Task details') : '';
        if (!det) { body.innerHTML = '<div class="osa-empty">Select a shift or a task to see its details.</div>'; return; }
        if (!det.data) { body.innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
        if (det.data.error) { body.innerHTML = `<div class="osa-empty">${esc(det.data.error)}</div>`; return; }
        body.innerHTML = det.kind === 'shift' ? shiftHtml(det.data) : taskHtml(det.data);
        body.scrollTop = 0;
        body.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => { const [k, id] = b.dataset.open.split(':'); openDetail(k, Number(id)); }));
    }

    function shiftHtml(d) {
        const tasks = arr(d.tasks), items = arr(d.payItems);
        let html = `<div class="ad-h"><h2>${esc(d.unit)} &middot; ${esc(BT.clean(d.player))}</h2>${d.live ? pill('On duty', '#2ea043') : pill('Ended', '#6e7682')}</div>
            <div class="ad-sub">Shift #${d.id} &middot; account ${esc(d.account || '-')}</div>`
            + kv([
                ['Started', d.startedAt],
                ['Ended', d.endedAt ? d.endedAt + ' (' + (REASON[d.reason] || d.reason || '-') + ')' : (d.live ? 'Still on duty' : '-')],
                ['Duration', BT.duration(d.duration)],
                ['Pay', money(d.pay)],
                ['Delivered', String(d.delivered)],
                ['Lost in transit / cancelled', d.inTransit + ' / ' + d.cancelled],
            ]);
        if (items.length) html += section('Pay breakdown') + items.map(i => `<div class="ad-row"><span class="grow">${esc(i.key)} &times;${i.count}</span><b>${money(i.amount)}</b></div>`).join('');
        html += section(`Tasks given to this shift (${tasks.length})`);
        html += tasks.length ? tasks.map(t => `<button class="ad-link" data-open="task:${t.id}"><b>T-${t.id}</b> ${esc(BT.what(t))}
            <small>${esc(t.fromName)} &rarr; ${esc(t.toName)} &middot; ${shortDate(t.assignedAt)} &rarr; ${t.releasedAt ? shortDate(t.releasedAt) : 'now'} &middot; ${esc(t.outcome || '-')} &middot; ${esc(BT.STATUS[t.status] || t.status)}</small></button>`).join('')
            : note('No task was given to this shift.');
        return html;
    }

    function taskHtml(d) {
        const log = arr(d.log), shifts = arr(d.shifts);
        let html = `<div class="ad-h"><h2>T-${d.id} &nbsp;${esc(BT.what(d))}</h2>${status(d.status)}</div>
            <div class="ad-sub">${esc(BT.TYPE[d.type] || d.type)}${d.urgency ? ' &middot; ' + esc(d.urgency) : ''}</div>`
            + kv([
                ['From', d.fromName], ['To', d.toName], ['Source', d.source],
                ['Created', d.createdAt], ['Picked up', d.pickedAt], ['Delivered', d.deliveredAt],
                ...(d.cancelledAt ? [['Cancelled', d.cancelledAt + ' (' + (d.cancelReason || '-') + ')']] : []),
            ]);
        html += section('History') + (log.length ? log.map(e => `<div class="ad-row"><span class="dim">${shortDate(e.at)}</span><b>${esc(e.event)}</b><span class="grow dim">${esc(e.info)}</span></div>`).join('') : note('No events.'));
        html += section(`Given to (${shifts.length})`);
        html += shifts.length ? shifts.map(s => `<button class="ad-link" data-open="shift:${s.shiftId}"><b>${esc(s.unit)}</b> &middot; ${esc(BT.clean(s.player))}
            <small>Shift #${s.shiftId} &middot; ${shortDate(s.assignedAt)} &rarr; ${s.releasedAt ? shortDate(s.releasedAt) : 'now'} &middot; ${esc(s.outcome || '-')}</small></button>`).join('')
            : note('No unit got this task.');
        return html;
    }
})();
