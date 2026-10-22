// v_admin web panel: the in-game admin panel (O key) in the browser.
// Players / Reports / Server / Commands. Sign-in with the game account; every action is
// checked again by the server (server/web.lua) with the same rules as in game.
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const { esc, arr } = OSA;
    const api = OSA.api();

    const S = {
        token: null,
        account: '',
        level: 0,
        inGame: false,
        info: null,          // { perms, ranks, commands, maxLevel }
        players: [],
        reports: [],
        tab: 'dashboard',
        selPlayer: null,     // player ID
        rpMode: 'active',    // active | logs
        selReport: null,     // report id
        logs: null,          // saved log index (null = not loaded)
        selLog: null,        // file name
        logData: null,
        seen: null,          // { reportId: message count } of the last poll
        poll: null,
    };

    const call = (fn, ...args) => api.call(fn, S.token, ...args);
    const perm = key => (S.info ? S.info.perms[key] : 99);
    const can = key => S.level >= perm(key);
    const rankName = lvl => { const r = S.info && arr(S.info.ranks).find(x => x.level === lvl); return r ? r.name : String(lvl); };
    const fmtInt = n => Math.floor(n || 0).toLocaleString('en-US');
    const val = v => (v === '' || v === undefined || v === null || v === false ? '-' : esc(v));

    function fmtDuration(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        const m = Math.floor(sec / 60), s = sec % 60;
        return m >= 60 ? `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m` : `${m}m ${String(s).padStart(2, '0')}s`;
    }

    function fmtDate(ts) {
        if (!ts) return '-';
        const d = new Date(ts * 1000), p = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
    }

    /* ============================================================ login */

    function loginError(t) { $('loginError').textContent = t || ''; }

    function leave() {
        S.token = null;
        if (S.poll) S.poll.stop();
        location.reload();
    }

    $('loginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('loginUser').value.trim(), pass = $('loginPass').value;
        if (!user || !pass) return;
        $('loginBtn').disabled = true;
        loginError('');
        try {
            const r = await api.call('adminWebLogin', null, user, pass);
            if (r && r.ok) {
                S.token = r.token;
                S.account = r.account;
                $('loginPass').value = '';
                document.body.classList.remove('locked');
                startPolling();
                setTab('dashboard');
            } else {
                loginError((r && r.error) || 'Login failed.');
                $('loginPass').select();
            }
        } catch (err) {
            loginError('Server unreachable: ' + err.message);
        }
        $('loginBtn').disabled = false;
    });

    $('logoutBtn').addEventListener('click', async () => {
        try { await call('adminWebLogout'); } catch (e) { /* ignore */ }
        leave();
    });

    setInterval(() => {
        const d = new Date(), p = n => String(n).padStart(2, '0');
        $('clock').textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    }, 1000);

    /* ============================================================ polling */

    function startPolling() {
        S.poll = OSA.poll(async () => {
            const r = await call('adminWebState', !S.info);
            if (r && r.error === 'unauthorized') return leave();
            if (!r || !r.ok) throw new Error((r && r.error) || 'bad response');
            if (r.info) S.info = r.info;
            if (r.time) OSA.time.sync(r.time);
            S.level = r.level;
            S.inGame = r.inGame;
            S.players = arr(r.players);
            S.reports = arr(r.reports).map(x => Object.assign(x, { messages: arr(x.messages) }));
            checkNewReports();
            render();
        }, 2500, {
            onOk: () => { $('conn').className = 'osa-conn ok'; },
            onFail: (n, e) => { $('conn').className = 'osa-conn bad'; if (n === 1) OSA.toast('Connection lost: ' + e.message); },
        });
    }

    // sound + toast for a new report / a new player message
    function beep() {
        try {
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const o = ctx.createOscillator(), g = ctx.createGain();
            o.connect(g); g.connect(ctx.destination);
            o.frequency.value = 880; g.gain.value = 0.08;
            o.start(); o.stop(ctx.currentTime + 0.18);
            setTimeout(() => ctx.close(), 400);
        } catch (e) { /* no audio */ }
    }

    function checkNewReports() {
        const now = {};
        for (const r of S.reports) now[r.id] = r.messages.length;
        if (S.seen) {
            for (const r of S.reports) {
                const before = S.seen[r.id];
                const last = r.messages[r.messages.length - 1];
                if (before === undefined) {
                    OSA.toast(`New report from ${r.playerName} (${r.playerId})`, true);
                    beep();
                } else if (r.messages.length > before && last && last.who === 'player') {
                    OSA.toast(`${r.playerName}: ${last.text}`, true);
                    beep();
                }
            }
        }
        S.seen = now;
    }

    // Runs a server call that returns { ok, messages }, shows the messages, refreshes.
    async function act(fn, ...args) {
        try {
            const r = await call(fn, ...args);
            if (r && r.error === 'unauthorized') { leave(); return null; }
            if (!r || r.ok === false && !arr(r.messages).length) {
                OSA.toast((r && r.error) || 'Request failed');
                return r;
            }
            for (const m of arr(r.messages)) OSA.toast(m.text, !m.bad);
            if (S.poll) S.poll.now();
            return r;
        } catch (e) {
            OSA.toast('Server unreachable: ' + e.message);
            return null;
        }
    }

    /* ============================================================ pages (left menu) */

    // A page request (server/pages.lua through adminWebCall). Resolves to { ok, result, message };
    // a request that answers later is asked again (adminWebResult) until it is done.
    async function page(name, action, args, quiet) {
        try {
            let r = await call('adminWebCall', name, action, args || {});
            for (let i = 0; r && r.pending && i < 60; i++) {
                await new Promise(res => setTimeout(res, 400));
                r = await call('adminWebResult', r.pending);
            }
            if (r && r.error === 'unauthorized') { leave(); return { ok: false }; }
            if (!r) return { ok: false };
            for (const m of arr(r.messages)) OSA.toast(m.text, !m.bad);
            if (r.message && !quiet) OSA.toast(r.message, r.ok);
            else if (!r.ok && r.error && !quiet) OSA.toast(r.error);
            return r;
        } catch (e) {
            if (!quiet) OSA.toast('Server unreachable: ' + e.message);
            return { ok: false };
        }
    }

    // grid table: cols = [{ key, label, cls, text(row) -> html, sort }], opts = { sel(row), click(row), sortKey, sortDir, onSort }
    function grid(el, cols, rows, opts) {
        opts = opts || {};
        const head = cols.map(c => `<th class="${c.cls || ''}${c.sort ? ' sort' : ''}${opts.sortKey === c.key ? ' on' : ''}" data-k="${c.key}">${esc(c.label)}${
            opts.sortKey === c.key ? (opts.sortDir === 'asc' ? ' ▲' : ' ▼') : ''}</th>`).join('');
        const body = rows.map((r, i) => `<tr data-i="${i}" class="${opts.click ? 'click' : ''}${opts.sel && opts.sel(r) ? ' sel' : ''}">${
            cols.map(c => `<td class="${c.cls || ''}">${c.text ? c.text(r) : val(r[c.key])}</td>`).join('')}</tr>`).join('');
        el.innerHTML = rows.length ? `<table class="grid"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`
            : `<div class="osa-empty">${esc(opts.empty || 'Nothing here.')}</div>`;
        el.onclick = e => {
            const th = e.target.closest('th.sort');
            if (th && opts.onSort) return opts.onSort(th.dataset.k);
            const tr = e.target.closest('tr[data-i]');
            if (tr && opts.click) opts.click(rows[Number(tr.dataset.i)]);
        };
    }

    // epoch seconds -> "5m ago" (server clock, synced on every poll)
    const ago = ts => {
        if (!ts) return '-';
        const s = Math.max(0, OSA.time.now() - ts);
        if (s < 60) return 'just now';
        if (s < 3600) return Math.floor(s / 60) + ' min ago';
        if (s < 86400) return Math.floor(s / 3600) + ' h ago';
        return Math.floor(s / 86400) + ' days ago';
    };
    const money = n => '€' + fmtInt(n);
    const PAGE_TITLES = {};
    document.querySelectorAll('#nav .nav-item').forEach(b => { PAGE_TITLES[b.dataset.page] = b.childNodes[0].textContent.trim(); });
    const PAGE_CATS = {};
    { let cat = ''; document.querySelectorAll('#nav > *').forEach(n => { if (n.classList.contains('cat')) cat = n.textContent; else PAGE_CATS[n.dataset.page] = cat; }); }
    const PAGES = {};      // [page] = { show(), render() }

    function setTab(tab, arg) {
        const b = document.querySelector(`#nav .nav-item[data-page="${tab}"]`);
        if (b && b.dataset.perm && !can(b.dataset.perm)) return OSA.toast(`You need admin level ${perm(b.dataset.perm)}.`);
        S.tab = tab;
        document.querySelectorAll('#nav .nav-item').forEach(x => x.classList.toggle('on', x.dataset.page === tab));
        document.querySelectorAll('.tab-page').forEach(p => { p.hidden = p.id !== 'page-' + tab; });
        $('pageTitle').textContent = PAGE_TITLES[tab] || tab;
        $('pageCrumb').textContent = `${PAGE_CATS[tab] || ''} › ${PAGE_TITLES[tab] || ''}`;
        if (PAGES[tab] && PAGES[tab].show) PAGES[tab].show(arg);
        render();
    }
    document.querySelectorAll('#nav .nav-item').forEach(b => b.addEventListener('click', () => setTab(b.dataset.page)));

    function render() {
        $('who').textContent = `${S.account} · ${rankName(S.level)} (${S.level})`;
        $('cntPlayers').textContent = S.players.length;
        $('onlinePill').textContent = `Online ${S.players.length} · ${S.players.filter(p => !p.logged).length} not logged in`;
        const waiting = S.reports.filter(r => r.status !== 'claimed').length;
        const cr = $('cntReports');
        cr.textContent = waiting || S.reports.length;
        cr.classList.toggle('hot', waiting > 0);
        document.querySelectorAll('#nav .nav-item[data-perm]').forEach(b => b.classList.toggle('lock', !can(b.dataset.perm)));
        if (S.tab === 'players') renderPlayers();
        else if (S.tab === 'reports') renderReports();
        else if (S.tab === 'server') renderServer();
        else if (S.tab === 'commands') renderCommands();
        else if (PAGES[S.tab] && PAGES[S.tab].render) PAGES[S.tab].render();
    }

    /* ============================================================ players */

    const ACTIONS = [
        { group: 'General' },
        { id: 'account', label: 'Open account', perm: 'accounts', show: p => p.account, local: p => setTab('accounts', p.account) },
        { id: 'goto', label: 'Go to', perm: 'teleport', needGame: true },
        { id: 'gethere', label: 'Bring here', perm: 'teleport', needGame: true },
        { id: 'spectate', label: 'Spectate (in game)', perm: 'spectate', needGame: true },
        { id: 'specoff', label: 'Stop spectating', perm: 'spectate', needGame: true, global: true },
        { id: 'heal', label: 'Heal', perm: 'heal' },
        { id: 'skin', label: 'Change skin', perm: 'skin', form: true },
        { group: 'Vehicle' },
        { id: 'fixveh', label: 'Fix vehicle', perm: 'vehicle' },
        { id: 'flipveh', label: 'Flip vehicle', perm: 'vehicle' },
        { id: 'getout', label: 'Pull out', perm: 'vehicle' },
        { group: 'Sanctions' },
        { id: 'mute', label: 'Mute', perm: 'mute', form: true, show: p => !p.muted },
        { id: 'unmute', label: 'Unmute', perm: 'mute', show: p => p.muted },
        { id: 'jail', label: 'Admin jail', perm: 'jail', form: true, show: p => !p.jailed },
        { id: 'unjail', label: 'Release from jail', perm: 'jail', show: p => p.jailed },
        { id: 'kick', label: 'Kick', perm: 'kick', form: true, danger: true },
        { group: 'Account' },
        { id: 'ban', label: 'Ban account', perm: 'ban', form: true, danger: true, show: p => !p.banned },
        { id: 'unban', label: 'Unban account', perm: 'ban', show: p => p.banned },
        { id: 'setlevel', label: 'Admin level', perm: 'setLevel', menu: true },
    ];

    const FORMS = {
        mute: { title: 'Mute', minutes: 30, submit: 'Mute', hint: 'The chat mute survives a relog and runs out on its own.' },
        jail: { title: 'Admin jail', minutes: 30, submit: 'Jail' },
        kick: { title: 'Kick', submit: 'Kick' },
        ban: { title: 'Ban account', submit: 'Ban', hint: 'Permanent account ban (acc_bans), the serial is stored too.' },
    };

    const selected = () => S.players.find(p => p.id === S.selPlayer);

    function renderPlayers() {
        const f = $('plFilter').value.trim().toLowerCase();
        const list = !f ? S.players : S.players.filter(p =>
            String(p.id) === f || p.name.toLowerCase().includes(f) || (p.account && p.account.toLowerCase().includes(f)));

        $('plRows').innerHTML = list.map(p => {
            const tags = [];
            if (p.adminLevel > 0) tags.push(`<span class="pl-tag admin">A${p.adminLevel}</span>`);
            if (!p.logged) tags.push('<span class="pl-tag">GUEST</span>');
            if (p.muted) tags.push('<span class="pl-tag warn">M</span>');
            if (p.jailed) tags.push('<span class="pl-tag warn">J</span>');
            if (p.banned) tags.push('<span class="pl-tag bad">B</span>');
            return `<div class="pl-row${p.id === S.selPlayer ? ' sel' : ''}" data-id="${p.id}">
                <span class="id">${p.id}</span><span class="nm">${esc(p.name)}</span><span class="tags">${tags.join('')}</span></div>`;
        }).join('') || '<div class="osa-empty">No players.</div>';
        $('plFoot').textContent = `${S.players.length} online` + (f ? ` · ${list.length} shown` : '');

        const p = selected();
        if (!p) {
            $('plDetail').innerHTML = '<div class="empty-center">Select a player</div>';
            $('plActions').innerHTML = '';
            return;
        }
        renderDetail(p);
        renderActions(p);
    }

    $('plRows').addEventListener('click', e => {
        const row = e.target.closest('.pl-row');
        if (!row) return;
        S.selPlayer = Number(row.dataset.id);
        renderPlayers();
    });
    $('plFilter').addEventListener('input', () => renderPlayers());

    function section(title, rows) {
        return `<div class="sec"><h3>${esc(title)}</h3><dl>${rows.map(r =>
            `<dt>${esc(r[0])}</dt><dd class="${r[2] || ''}" data-copy="${esc(r[1])}">${val(r[1])}</dd>`).join('')}</dl></div>`;
    }

    function renderDetail(p) {
        const sanctions = [['Muted', p.muted ? `yes (${fmtDuration(p.muteLeft)} left)` : 'no', p.muted ? 'warn' : '']];
        if (p.muted) sanctions.push(['Mute reason', `${p.muteReason || '?'} (${p.muteAdmin || '?'})`]);
        sanctions.push(['Admin jail', p.jailed ? `yes (${p.jailLeft} min left)` : 'no', p.jailed ? 'warn' : '']);
        if (p.jailed) sanctions.push(['Jail reason', `${p.jailReason || '?'} (${p.jailAdmin || '?'})`]);
        sanctions.push(['Banned', p.banned ? 'yes' : 'no', p.banned ? 'bad' : '']);
        if (p.banned) sanctions.push(['Ban', `${p.banReason || '?'} (${p.banAdmin || '?'}, ${p.banDate || '?'})`]);

        const el = $('plDetail');
        const top = el.scrollTop;
        el.innerHTML = `<h2>${esc(p.name)}</h2><div class="sub">ID ${p.id}${p.account ? ' · ' + esc(p.account) : ' · not logged in'}</div>
        <div class="cols">
          <div>
            ${section('Account', [
                ['Name', p.name], ['ID', p.id],
                ['Account', p.account || 'not logged in', p.account ? '' : 'dim'],
                ['Account ID', p.accountId], ['E-mail', p.email], ['Registered', fmtDate(p.created)],
                ['Admin level', `${p.adminLevel}  ${p.rank}`, p.adminLevel > 0 ? 'warn' : ''],
            ])}
            ${section('Character', [
                ['Health / armour', `${p.dead ? 'DEAD' : p.health} / ${p.armor}`, p.dead ? 'bad' : ''],
                ['Cash', '€' + fmtInt(p.cash), 'good'],
                ['Bank', p.bank === false ? '-' : '€' + fmtInt(p.bank), p.bank === false ? '' : 'good'],
                ['Level / XP', `${p.level === false ? '-' : p.level} / ${p.xp === false ? '-' : fmtInt(p.xp)}`],
                ['Played time', p.playtime], ['Work', p.work], ['Skin', p.skin],
            ])}
          </div>
          <div>
            ${section('Connection', [
                ['Serial', p.serial], ['IP', p.ip], ['Ping', p.ping, p.ping > 200 ? 'warn' : ''], ['Client version', p.version],
            ])}
            ${section('Location', [
                ['Zone', p.zone], ['Position', arr(p.pos).join(', ')], ['Interior / dim', `${p.interior} / ${p.dimension}`],
                ['Vehicle', p.vehicle ? `${p.vehicle} (${p.vehicleHp} HP)` : '-'],
            ])}
            ${section('Sanctions', sanctions)}
          </div>
        </div>`;
        el.scrollTop = top;
    }

    $('plDetail').addEventListener('click', e => {
        const dd = e.target.closest('dd[data-copy]');
        if (!dd || !navigator.clipboard) return;
        navigator.clipboard.writeText(dd.dataset.copy).then(() => OSA.toast('Copied to clipboard', true), () => {});
    });

    function renderActions(p) {
        let html = '', group = '', pending = '';
        for (const a of ACTIONS) {
            if (a.group) { pending = `<h4>${esc(a.group)}</h4>`; continue; }
            if (a.show && !a.show(p)) continue;
            const ok = can(a.perm) && !(a.needGame && !S.inGame);
            const hint = !can(a.perm) ? `Needs admin level ${perm(a.perm)}`
                : (a.needGame && !S.inGame) ? 'You need to be online in game on this account' : '';
            html += pending; pending = '';
            html += `<button class="osa-btn${a.danger ? ' danger-text' : ''}${ok ? '' : ' lock'}" data-act="${a.id}" title="${esc(hint)}">
                <span>${esc(a.label)}</span><small>${can(a.perm) ? '' : 'Lv ' + perm(a.perm)}</small></button>`;
        }
        $('plActions').innerHTML = html;
    }

    $('plActions').addEventListener('click', async e => {
        const btn = e.target.closest('button[data-act]');
        const p = selected();
        if (!btn || !p) return;
        const a = ACTIONS.find(x => x.id === btn.dataset.act);
        if (!a) return;
        if (!can(a.perm)) return OSA.toast(`You need admin level ${perm(a.perm)}.`);
        if (a.needGame && !S.inGame) return OSA.toast('You need to be online in game on this account.');

        if (a.local) return a.local(p);
        if (a.global) return act('adminWebAction', a.id, null);
        if (a.menu) return levelMenu(p, btn);
        if (a.id === 'skin') {
            const r = await OSA.ui.form(`Change skin: ${p.name} (${p.id})`,
                [{ name: 'skin', label: 'Skin ID', type: 'number', value: String(p.skin) }], 'Change',
                'Valid ped model ID. A player on work duty is taken off duty first.');
            if (!r) return;
            if (!(Number(r.skin) >= 0) || r.skin === '') return OSA.toast('Enter a skin ID.');
            return act('adminWebAction', 'skin', p.id, Number(r.skin));
        }
        if (a.form) {
            const def = FORMS[a.id];
            const fields = [];
            if (def.minutes) fields.push({ name: 'minutes', label: 'Minutes', type: 'number', value: String(def.minutes) });
            fields.push({ name: 'reason', label: 'Reason', type: 'text' });
            const r = await OSA.ui.form(`${def.title}: ${p.name} (${p.id})`, fields, def.submit, def.hint);
            if (!r) return;
            if (def.minutes && !(Number(r.minutes) >= 1)) return OSA.toast('Enter the duration in minutes.');
            if (!r.reason) return OSA.toast('Enter a reason.');
            return act('adminWebAction', a.id, p.id, def.minutes ? Number(r.minutes) : r.reason, def.minutes ? r.reason : undefined);
        }
        return act('adminWebAction', a.id, p.id);
    });

    function levelMenu(p, btn) {
        const max = S.info.maxLevel;
        const maxGrant = S.level >= max ? max : S.level - 1;
        const items = [{ header: `Admin level of ${p.name}` }];
        for (let lvl = 0; lvl <= max; lvl++) {
            items.push({
                label: `${lvl}  ${rankName(lvl)}${lvl === p.adminLevel ? '  (current)' : ''}`,
                disabled: lvl > maxGrant || lvl === p.adminLevel,
                action: () => act('adminWebAction', 'setlevel', p.id, lvl),
            });
        }
        const r = btn.getBoundingClientRect();
        OSA.ui.openMenu(r.left, r.bottom + 2, items);
    }

    /* ============================================================ reports */

    $('rpMode').addEventListener('click', e => {
        const b = e.target.closest('.osa-tab');
        if (!b) return;
        S.rpMode = b.dataset.mode;
        reportSig.rows = reportSig.chat = '';
        $('rpMode').querySelectorAll('.osa-tab').forEach(x => x.classList.toggle('active', x === b));
        if (S.rpMode === 'logs') loadLogs();
        renderReports();
    });

    async function loadLogs() {
        S.logs = null;
        const r = await call('adminWebLogs');
        if (r && r.error === 'unauthorized') return leave();
        S.logs = r && r.ok ? arr(r.list) : [];
        if (!(r && r.ok)) OSA.toast((r && r.error) || 'Could not load the logs.');
        renderReports();
    }

    const reportSig = { rows: '', chat: '' };

    function renderReports() {
        if (!can('reports')) {
            $('rpRows').innerHTML = '';
            $('rpChat').innerHTML = `<div class="empty-center">Needs admin level ${perm('reports')}.</div>`;
            return;
        }
        if (S.rpMode === 'logs') return renderLogs();
        renderActiveRows();
        renderChat();
    }

    function renderActiveRows() {
        const html = S.reports.map(r => {
            const last = r.messages[r.messages.length - 1];
            const status = r.status === 'claimed'
                ? `<span class="osa-pill ok">${esc(r.claimedByName)}</span>` : '<span class="osa-pill warn">waiting</span>';
            return `<div class="rp-row${r.id === S.selReport ? ' sel' : ''}" data-id="${r.id}">
                <div class="top"><span>${esc(r.playerName)} <span class="osa-muted">(${r.playerId})</span>${r.online ? '' : ' <span class="osa-muted">offline</span>'}</span>${status}</div>
                <div class="last">${last ? esc(last.text) : ''}</div></div>`;
        }).join('') || '<div class="osa-empty">No active reports.</div>';
        if (html !== reportSig.rows) { $('rpRows').innerHTML = html; reportSig.rows = html; }
    }

    $('rpRows').addEventListener('click', e => {
        const row = e.target.closest('.rp-row');
        if (!row) return;
        if (S.rpMode === 'logs') {
            S.selLog = row.dataset.file;
            S.logData = null;
            call('adminWebLogs', S.selLog).then(r => {
                if (r && r.ok && r.file === S.selLog) { S.logData = r.log; renderChat(); }
                else OSA.toast((r && r.error) || 'Could not read the log.');
            });
        } else {
            S.selReport = Number(row.dataset.id);
        }
        reportSig.rows = reportSig.chat = '';
        renderReports();
    });

    function msgHtml(m) {
        return `<div class="msg ${m.who}"><time>${esc(m.time)}</time>${m.who === 'system' ? '' : `<span class="who">${esc(m.name || '')}</span>`}${esc(m.text)}</div>`;
    }

    function renderChat() {
        const box = $('rpChat');

        if (S.rpMode === 'logs') {
            const lsig = 'log:' + (S.logData ? S.selLog : '');
            if (lsig === reportSig.chat) return;
            reportSig.chat = lsig;
            if (!S.logData) { box.innerHTML = '<div class="empty-center">Select a log</div>'; return; }
            const info = S.logData.info || {};
            box.innerHTML = `<div class="rp-head"><div class="title"><b>${esc(info.player || '')}</b><span class="osa-muted">Admin: ${esc(info.adminClaimed || '-')}</span></div></div>
                <div class="rp-msgs">${arr(S.logData.messages).map(m => {
                    const mine = m.sender && m.sender === info.adminClaimed ? 'admin' : (m.sender && m.sender === info.player ? 'player' : 'system');
                    return `<div class="msg ${mine}"><time>${esc(m.time)}</time>${mine === 'system' ? '' : `<span class="who">${esc(m.sender)}</span>`}${esc(m.text)}</div>`;
                }).join('')}</div>`;
            return;
        }

        const r = S.reports.find(x => x.id === S.selReport);
        if (!r) {
            if (reportSig.chat !== 'none') { box.innerHTML = '<div class="empty-center">Select a report</div>'; reportSig.chat = 'none'; }
            return;
        }
        const sig = JSON.stringify([r.id, r.status, r.claimedByName, r.online, r.messages.length, S.inGame]);
        if (sig === reportSig.chat) return;
        reportSig.chat = sig;

        const old = $('rpInput');
        const keep = old ? { v: old.value, focus: document.activeElement === old } : null;
        const msgs = box.querySelector('.rp-msgs');
        const stick = !msgs || msgs.scrollHeight - msgs.scrollTop - msgs.clientHeight < 40;

        box.innerHTML = `<div class="rp-head">
                <div class="title"><b>${esc(r.playerName)} (${r.playerId})</b><span class="osa-muted">${r.status === 'claimed' ? 'Claimed by ' + esc(r.claimedByName) : 'Waiting for an admin'}${r.online ? '' : ' · offline'}</span></div>
                <button class="osa-btn small" data-rp="claim">Claim</button>
                <button class="osa-btn small" data-rp="tp"${r.online && S.inGame ? '' : ' disabled'} title="${S.inGame ? '' : 'You need to be online in game on this account'}">Teleport</button>
                <button class="osa-btn small danger" data-rp="close">Close</button>
            </div>
            <div class="rp-msgs">${r.messages.map(m => msgHtml(m)).join('')}</div>
            <form class="rp-send" id="rpForm"><input class="osa-input grow" id="rpInput" type="text" maxlength="300" placeholder="Message (an unclaimed report is claimed when you write)" autocomplete="off"><button class="osa-btn primary" type="submit">Send</button></form>`;

        const nm = box.querySelector('.rp-msgs');
        if (stick) nm.scrollTop = nm.scrollHeight;
        if (keep) { const i = $('rpInput'); i.value = keep.v; if (keep.focus) i.focus(); }
    }

    $('rpChat').addEventListener('submit', async e => {
        if (e.target.id !== 'rpForm') return;
        e.preventDefault();
        const input = $('rpInput'), text = input.value.trim();
        if (!text || !S.selReport) return;
        input.value = '';
        const r = await act('adminWebReport', 'message', S.selReport, text);
        if (r && r.ok === false) input.value = text;
        reportSig.chat = '';
    });

    $('rpChat').addEventListener('click', async e => {
        const b = e.target.closest('button[data-rp]');
        if (!b || !S.selReport) return;
        const op = b.dataset.rp, id = S.selReport;
        if (op === 'close' && !(await OSA.ui.confirm('Close report', 'The report is saved to the logs and closed for the player.', 'Close report'))) return;
        await act('adminWebReport', op, id);
        reportSig.chat = '';
    });

    function renderLogs() {
        const html = S.logs === null ? '<div class="osa-empty">Loading...</div>'
            : !S.logs.length ? '<div class="osa-empty">No saved logs.</div>'
            : S.logs.map(l => `<div class="rp-row${l.file === S.selLog ? ' sel' : ''}" data-file="${esc(l.file)}">
                <div class="top"><span>${esc(l.player)}</span><span class="osa-muted">${esc(l.date)}</span></div>
                <div class="last">Admin: ${esc(l.admin || '-')}</div></div>`).join('');
        if (html !== reportSig.rows) { $('rpRows').innerHTML = html; reportSig.rows = html; }
        renderChat();
    }

    /* ============================================================ server */

    $('svAnnounce').addEventListener('input', () => { $('svAnnCount').textContent = `${$('svAnnounce').value.length} / 200`; });

    $('svAnnBtn').addEventListener('click', async () => {
        if (!can('adminCall')) return OSA.toast(`You need admin level ${perm('adminCall')}.`);
        const text = $('svAnnounce').value.trim();
        if (!text) return OSA.toast('Write the announcement first.');
        const r = await act('adminWebAction', 'announce', null, text);
        if (r && r.ok) { $('svAnnounce').value = ''; $('svAnnCount').textContent = '0 / 200'; }
    });

    async function unban() {
        if (!can('ban')) return OSA.toast(`You need admin level ${perm('ban')}.`);
        const acc = $('svUnban').value.trim();
        if (!acc) return OSA.toast('Enter an account name.');
        const r = await act('adminWebAction', 'unbanAccount', null, acc);
        if (r && r.ok) $('svUnban').value = '';
    }
    $('svUnbanBtn').addEventListener('click', unban);
    $('svUnban').addEventListener('keydown', e => { if (e.key === 'Enter') unban(); });

    function renderServer() {
        const lvl = key => `Level ${perm(key)}${can(key) ? '' : ' · locked'}`;
        $('svAnnLevel').textContent = lvl('adminCall');
        $('svBanLevel').textContent = lvl('ban');
        $('svAnnBtn').disabled = !can('adminCall');
        $('svUnbanBtn').disabled = !can('ban');

        const guests = S.players.filter(p => !p.logged).length;
        const muted = S.players.filter(p => p.muted).length;
        const jailed = S.players.filter(p => p.jailed).length;
        const admins = S.players.filter(p => p.adminLevel > 0).sort((a, b) => b.adminLevel - a.adminLevel);
        const d = new Date(), p2 = n => String(n).padStart(2, '0');
        const rows = [
            ['Time', `${d.getFullYear()}.${p2(d.getMonth() + 1)}.${p2(d.getDate())}  ${p2(d.getHours())}:${p2(d.getMinutes())}`],
            ['Players online', `${S.players.length} (${guests} not logged in)`],
            ['Muted / jailed', `${muted} / ${jailed}`],
            ['Admins online', admins.length],
        ];
        $('svOverview').innerHTML = `<div class="osa-panel-head"><strong>Server</strong></div><div class="card-body">
            <div class="sec"><dl>${rows.map(r => `<dt>${r[0]}</dt><dd>${esc(r[1])}</dd>`).join('')}</dl></div>
            <div class="sec"><h3>Admins online</h3><dl>${admins.map(a =>
                `<dt>${esc(a.name)} (${a.id})</dt><dd>${a.adminLevel}  ${esc(a.rank)}</dd>`).join('') || '<dt>-</dt><dd></dd>'}</dl></div></div>`;
    }

    /* ============================================================ commands */

    let commandsDone = false;
    function renderCommands() {
        if (commandsDone || !S.info) return;
        commandsDone = true;
        $('cmdList').innerHTML = `<table class="osa-table sticky"><thead><tr><th>Command</th><th>Level</th><th>Description</th></tr></thead><tbody>${
            arr(S.info.commands).map(c => `<tr><td><code>${esc(c.cmd)}</code></td><td class="c">${c.level > 0 ? c.level : 'all'}</td><td>${esc(c.desc)}</td></tr>`).join('')
        }</tbody></table>`;
    }
    /* ============================================================ dashboard */

    const D = { data: null };
    PAGES.dashboard = {
        async show() {
            const r = await page('dashboard', 'summary', {}, true);
            if (r.ok) { D.data = r.result; PAGES.dashboard.render(); }
        },
        render() {
            const d = D.data;
            if (!d) { $('dashTiles').innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
            const tile = (label, value, cls, go) => `<div class="tile" data-go="${go || ''}"><span>${esc(label)}</span><b class="${cls || ''}">${esc(value)}</b></div>`;
            $('dashTiles').innerHTML =
                tile('Players online', `${d.online} / ${d.maxPlayers}`, 'good', 'players') +
                tile('Reports waiting / active', `${d.reportsWaiting} / ${d.reports}`, d.reportsWaiting > 0 ? 'bad' : '', 'reports') +
                tile('Active bans', fmtInt(d.activeBans), '', 'bans') +
                tile('Accounts', d.accounts === false ? '-' : fmtInt(d.accounts), '', 'accounts') +
                tile('Muted / jailed', `${d.muted} / ${d.jailed}`, d.muted + d.jailed > 0 ? 'warn' : '', 'bans');
            const w = d.week;
            $('dashWeek').innerHTML = w ? `<p class="dim">${esc(w.from)} – ${esc(w.to)}</p>
                <p><span class="dim">Time trial:</span> ${val(w.timetrial)}</p>
                <p><span class="dim">Login bonus:</span> ${w.loginBonus ? `<span class="good">${money(w.loginBonus.money)} + ${fmtInt(w.loginBonus.xp)} XP</span>` : '-'}</p>
                <p class="dim">Job bonuses</p>${arr(w.jobs).map(j => `<p>${esc(j)}</p>`).join('') || '<p>-</p>'}
                ${d.instance ? `<p class="dim">Server: ${esc(d.instance)}</p>` : ''}` : '<p>-</p>';
            $('dashAdmins').innerHTML = (arr(d.admins).map(a => `<div class="row"><span>${esc(a.name)} (${a.id})</span><span class="gold">${esc(rankName(a.level))}</span></div>`).join('') || '<p>-</p>')
                + `<div class="secttl">Resources failed to load</div>` + (arr(d.failed).map(n => `<p class="bad">${esc(n)}</p>`).join('') || '<p class="good">None</p>');
            grid($('dashLog'), [
                { key: 'ts', label: 'When', text: r => esc(ago(r.ts)) },
                { key: 'admin', label: 'Admin' },
                { key: 'action', label: 'Action' },
            ], arr(d.log), { empty: 'No admin actions yet.', click: can('adminLog') ? () => setTab('adminlog') : null });
        },
    };
    $('dashTiles').addEventListener('click', e => { const t = e.target.closest('.tile'); if (t && t.dataset.go) setTab(t.dataset.go); });

    /* ============================================================ accounts */

    const A = {
        args: { admin: 'any', status: 'any', registered: 'any', email: 'any', updates: 'any', conds: [], sort: 'name', dir: 'asc', page: 0, search: '' },
        data: null, sel: null, detail: null, tab: 'overview', tabData: {}, tabSel: {}, mail: null, filters: [],
    };
    const ACC_FILTERS = [
        { key: 'admin', label: 'Admin', values: () => [['any', 'Any'], ['admins', 'Admins only']].concat(
            Array.from({ length: (S.info ? S.info.maxLevel : 6) + 1 }, (_, l) => [String(l), `${l} ${rankName(l)}`])) },
        { key: 'status', label: 'Status', values: () => [['any', 'Any'], ['online', 'Online'], ['offline', 'Offline'], ['banned', 'Banned'], ['muted', 'Muted'], ['jailed', 'Jailed']] },
        { key: 'registered', label: 'Registered', values: () => [['any', 'Any'], ['1', 'Last day'], ['7', 'Last 7 days'], ['30', 'Last 30 days'], ['365', 'Last year']] },
        { key: 'email', label: 'E-mail', values: () => [['any', 'Any'], ['yes', 'Has e-mail'], ['no', 'No e-mail']] },
        { key: 'updates', label: 'Update mails', values: () => [['any', 'Any'], ['yes', 'Subscribed'], ['no', 'Unsubscribed']] },
    ];
    const ACC_CONDS = [['money', 'Cash'], ['bank', 'Bank'], ['level', 'Level'], ['xp', 'XP'], ['playtime', 'Playtime (h)'], ['vehicles', 'Vehicles'], ['adminLevel', 'Admin level'], ['id', 'Account ID']];

    let accTimer = null;
    async function accList(refresh) {
        const r = await page('accounts', 'list', Object.assign({}, A.args, { refresh: !!refresh }), true);
        if (r.ok) A.data = r.result;
        accRender();
    }

    function accFilters() {
        $('accFilters').innerHTML = `<input class="osa-input" id="accSearch" type="search" placeholder="Name, display name, e-mail or ID" value="${esc(A.args.search)}" autocomplete="off">`
            + ACC_FILTERS.map(f => {
                const v = f.values().find(x => x[0] === A.args[f.key]);
                return `<button class="osa-btn${A.args[f.key] !== 'any' ? ' active' : ''}" data-f="${f.key}">${esc(f.label)}: ${esc(v ? v[1] : A.args[f.key])}</button>`;
            }).join('')
            + '<button class="osa-btn" id="accAddCond">+ Filter</button><button class="osa-btn" id="accClear">Clear</button><button class="osa-btn" id="accReload">Reload</button><button class="osa-btn" id="accExport">Export CSV</button>'
            + `<button class="osa-btn" id="accSaved"${A.filters.length ? '' : ' disabled'}>Saved filters (${A.filters.length})</button><button class="osa-btn" id="accSave">Save filter</button>`;
        $('accSearch').addEventListener('input', e => {
            A.args.search = e.target.value.trim();
            A.args.page = 0;
            clearTimeout(accTimer);
            accTimer = setTimeout(accList, 400);
        });
    }

    $('accFilters').addEventListener('click', e => {
        const b = e.target.closest('button');
        if (!b) return;
        const r = b.getBoundingClientRect();
        if (b.dataset.f) {
            const f = ACC_FILTERS.find(x => x.key === b.dataset.f);
            OSA.ui.openMenu(r.left, r.bottom + 2, f.values().map(v => ({ label: v[1], action: () => { A.args[f.key] = v[0]; A.args.page = 0; accFilters(); accList(); } })));
        } else if (b.id === 'accAddCond') {
            OSA.ui.openMenu(r.left, r.bottom + 2, ACC_CONDS.map(c => ({ label: c[1], action: () => { A.args.conds.push({ key: c[0], op: '>=', value: '' }); accConds(); } })));
        } else if (b.id === 'accClear') {
            Object.assign(A.args, { admin: 'any', status: 'any', registered: 'any', email: 'any', updates: 'any', conds: [], page: 0, search: '' });
            accFilters(); accConds(); accList();
        } else if (b.id === 'accReload') accList(true);
        else if (b.id === 'accExport') accExport();
        else if (b.id === 'accSave') accSaveFilter();
        else if (b.id === 'accSaved') {
            const items = A.filters.map(f => ({ label: f.name, action: () => accApplyFilter(f) }));
            if (items.length) items.push({ header: 'Delete' });
            for (const f of A.filters) items.push({ label: `Delete "${f.name}"`, danger: true, action: async () => {
                const r = await page('accounts', 'delfilter', { name: f.name }, true);
                if (r.ok) { A.filters = arr(r.result.list); accFilters(); }
            } });
            OSA.ui.openMenu(r.left, r.bottom + 2, items);
        }
    });

    async function accExport() {
        const args = Object.assign({}, A.args);
        delete args.page;
        const r = await page('accounts', 'export', args, true);
        if (!r.ok || !r.result || !r.result.csv) return OSA.toast(r.message || 'Export failed.');
        const url = URL.createObjectURL(new Blob(['﻿' + r.result.csv], { type: 'text/csv;charset=utf-8' }));
        const a = document.createElement('a');
        a.href = url;
        a.download = `accounts_${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
        OSA.toast(`${r.result.count} of ${r.result.total} accounts exported.`, true);
    }

    async function accSaveFilter() {
        const f = await OSA.ui.form('Save filter', [{ name: 'name', label: 'Name', type: 'text' }], 'Save');
        if (!f || !f.name) return;
        const filter = Object.assign({}, A.args, { conds: A.args.conds.map(c => Object.assign({}, c)) });
        delete filter.page;
        const r = await page('accounts', 'savefilter', { name: f.name, filter });
        if (r.ok) { A.filters = arr(r.result.list); accFilters(); }
    }

    function accApplyFilter(sf) {
        const f = sf.filter || {};
        Object.assign(A.args, { admin: f.admin || 'any', status: f.status || 'any', registered: f.registered || 'any', email: f.email || 'any',
            updates: f.updates || 'any', conds: arr(f.conds).map(c => ({ key: c.key, op: c.op || '>=', value: String(c.value || '') })),
            sort: f.sort || 'name', dir: f.dir || 'asc', search: f.search || '', page: 0 });
        accFilters(); accConds(); accList();
    }

    function accConds() {
        $('accConds').innerHTML = A.args.conds.map((c, i) => `<span class="cond" data-i="${i}">${esc((ACC_CONDS.find(x => x[0] === c.key) || [0, c.key])[1])}
            <button data-op="${i}">${esc(c.op)}</button><input class="osa-input" data-v="${i}" value="${esc(c.value)}" inputmode="numeric"><button data-del="${i}">✕</button></span>`).join('');
    }
    $('accConds').addEventListener('click', e => {
        const b = e.target.closest('button');
        if (!b) return;
        if (b.dataset.op !== undefined) {
            const c = A.args.conds[Number(b.dataset.op)];
            c.op = { '>=': '<=', '<=': '=', '=': '>=' }[c.op];
        } else if (b.dataset.del !== undefined) A.args.conds.splice(Number(b.dataset.del), 1);
        accConds();
        A.args.page = 0;
        accList();
    });
    $('accConds').addEventListener('change', e => {
        if (e.target.dataset.v === undefined) return;
        A.args.conds[Number(e.target.dataset.v)].value = e.target.value.replace(/[^\d]/g, '');
        A.args.page = 0;
        accList();
    });

    function accStatus(r) {
        if (r.banned) return '<span class="bad">banned</span>';
        if (r.jailed) return '<span class="warn">jailed</span>';
        if (r.muted) return '<span class="warn">muted</span>';
        return '<span class="dim">ok</span>';
    }

    function accRender() {
        const d = A.data;
        $('accMeta').textContent = d ? `${fmtInt(d.total)} matches of ${fmtInt(d.all)} accounts · list read ${ago(d.cachedAt)}` : 'Loading...';
        grid($('accRows'), [
            { key: 'name', label: 'Account', sort: true, text: r => `${r.online ? '<span class="good">●</span> ' : ''}<b>${esc(r.name)}</b>` },
            { key: 'display', label: 'Display name', sort: true },
            { key: 'adminLevel', label: 'Adm', sort: true, cls: 'c narrow', text: r => r.adminLevel > 0 ? `<b class="gold" title="${esc(rankName(r.adminLevel))}">${r.adminLevel}</b>` : '-' },
            { key: 'level', label: 'Level', sort: true, cls: 'r' },
            { key: 'vehicles', label: 'Vehicles', sort: true, cls: 'r' },
            { key: 'lastLogin', label: 'Last seen', sort: true, text: r => r.online ? `<span class="good">online · ID ${r.online}</span>` : esc(ago(r.lastLogin)) },
            { key: 'status', label: 'Status', text: accStatus },
        ], d ? arr(d.rows) : [], {
            sortKey: A.args.sort, sortDir: A.args.dir,
            onSort: k => {
                if (A.args.sort === k) A.args.dir = A.args.dir === 'asc' ? 'desc' : 'asc';
                else { A.args.sort = k; A.args.dir = (k === 'name' || k === 'display') ? 'asc' : 'desc'; }
                A.args.page = 0;
                accList();
            },
            sel: r => r.name === A.sel, click: r => accSelect(r.name), empty: d ? 'No account matches.' : 'Loading...',
        });
        $('accPager').innerHTML = d ? `<button class="osa-btn small" data-p="-1"${d.page > 0 ? '' : ' disabled'}>‹</button>
            <span>Page ${d.page + 1} / ${d.pages}</span><button class="osa-btn small" data-p="1"${d.page < d.pages - 1 ? '' : ' disabled'}>›</button>` : '';
        accDetail();
    }
    $('accPager').addEventListener('click', e => {
        const b = e.target.closest('button[data-p]');
        if (!b || b.disabled) return;
        A.args.page += Number(b.dataset.p);
        accList();
    });

    async function accLoadDetail() {
        const name = A.sel;
        const r = await page('accounts', 'detail', { name });
        if (A.sel !== name) return;
        A.detail = r.ok ? r.result : false;
        accDetail();
        if (A.tab !== 'overview' && A.tab !== 'notes') accLoadTab(A.tab);
    }

    async function accLoadTab(tab) {
        const name = A.sel;
        A.tabData[tab] = null;
        const r = await page('accounts', 'tab', { name, tab }, true);
        if (A.sel !== name) return;
        A.tabData[tab] = r.ok ? r.result : { list: [] };
        accDetail();
    }

    function accSelect(name) {
        if (A.sel === name) return;
        Object.assign(A, { sel: name, detail: null, tabData: {}, tabSel: {}, mail: null });
        accRender();
        accLoadDetail();
    }

    async function accEdit(what, extra) {
        const r = await page('accounts', 'edit', Object.assign({ name: A.sel, what }, extra || {}));
        if (r.ok) { accLoadDetail(); accList(true); }
        return r;
    }

    async function accAsk(what, title, label, value, extra, numeric) {
        const f = await OSA.ui.form(title, [{ name: 'v', label, type: numeric ? 'number' : (what === 'note' ? 'textarea' : 'text'), value: value === undefined ? '' : String(value) }], 'Save');
        if (!f || f.v === '') return;
        const key = what === 'ban' ? 'reason' : what === 'note' ? 'text' : what === 'vehgive' ? 'model' : 'value';
        accEdit(what, Object.assign({ [key]: f.v }, extra || {}));
    }

    const ACC_TABS = [['overview', 'Overview'], ['stats', 'Stats'], ['vehicles', 'Vehicles'], ['mails', 'Mails'], ['punishments', 'Punishments'],
        ['achievements', 'Achievements'], ['inventory', 'Inventory'], ['social', 'Social'], ['notes', 'Notes']];

    function accDetail() {
        const el = $('accDetail');
        const d = A.detail;
        if (!A.sel) { el.innerHTML = '<div class="empty-center">Select an account</div>'; return; }
        if (d === null) { el.innerHTML = '<div class="empty-center">Loading...</div>'; return; }
        if (d === false) { el.innerHTML = '<div class="empty-center bad">No such account</div>'; return; }
        const kv = (l, v, cls) => `<div class="kvt"><span>${esc(l)}</span><b class="${cls || ''}">${val(v)}</b></div>`;
        let body = '';
        const t = A.tabData[A.tab];
        const loading = '<div class="osa-empty">Loading...</div>';
        if (A.tab === 'overview') {
            body = `<div class="tilesgrid">
                ${kv('E-mail', d.email)}${kv('Update mails', d.hasEmail ? (d.updates ? 'Subscribed' : 'Unsubscribed') : '-', d.updates ? 'good' : 'dim')}
                ${kv('Cash', money(d.money), 'good')}${kv('Bank', money(d.bank), 'good')}${kv('Level · XP', `${d.level} · ${fmtInt(d.xp)}`)}
                ${kv('Playtime', d.playtimeText || `${Math.floor(d.playtime / 60)}h ${String(d.playtime % 60).padStart(2, '0')}m`)}
                ${kv('Last login', d.online ? 'online now' : fmtDate(d.lastLogin))}
                ${kv('Last serial', d.lastSerial)}${kv('Last IP', d.lastIp)}
                ${kv('Achievements', d.achievements ? `${d.achievements.done} / ${d.achievements.total}` : '-')}${kv('Vehicles', d.vehicles)}
            </div>${d.banned ? `<div class="banbar">Banned by ${esc(d.banned.admin || '?')}: ${esc(d.banned.reason || '?')}</div>` : ''}
            <div class="secttl">Work levels</div>${arr(d.works).map(w => `<div class="row"><span>${esc(w.name)}</span><span class="dim">level ${w.level} / ${w.maxLevel} · ${fmtInt(w.xp)} XP</span>
                ${can('accountEdit') ? `<button class="osa-btn small" data-workxp="${esc(w.id)}" data-xp="${w.xp}">Set XP</button>` : ''}</div>`).join('') || '<p class="dim">-</p>'}`;
        } else if (A.tab === 'notes') {
            body = `<div id="accTab"></div><div class="acc-actions"><button class="osa-btn" data-act="note">Add note</button></div>`;
        } else {
            body = t ? '<div id="accTab"></div>' : loading;
        }
        const actions = A.tab !== 'overview' ? '' : `<div class="acc-actions">
            ${d.online && can('teleport') && S.inGame ? `<button class="osa-btn" data-act="goto">Go to</button>` : ''}
            ${can('setLevel') ? '<button class="osa-btn" data-act="setlevel">Set admin level</button>' : ''}
            ${can('accountEdit') ? '<button class="osa-btn" data-act="money">Edit cash</button><button class="osa-btn" data-act="bank">Edit bank</button><button class="osa-btn" data-act="level">Edit level</button><button class="osa-btn" data-act="xp">Edit XP</button>' : ''}
            ${can('email') ? '<button class="osa-btn" data-act="email">Set e-mail</button>' : ''}
            ${can('passwordReset') && d.hasEmail ? '<button class="osa-btn" data-act="pwreset">Send password reset</button>' : ''}
            ${can('mail') && d.hasEmail ? '<button class="osa-btn" data-act="mail">Send mail</button>' : ''}
            ${can('mute') && d.muted ? '<button class="osa-btn" data-act="unmute">Unmute</button>' : ''}
            ${can('ban') ? (d.banned ? '<button class="osa-btn" data-act="unban">Unban</button>' : '<button class="osa-btn danger" data-act="ban">Ban account</button>') : ''}
        </div>`;
        el.innerHTML = `<div class="acc-head"><div class="acc-av">${esc(d.name.charAt(0).toUpperCase())}</div><div>
                <h2>${esc(d.name)} ${d.adminLevel > 0 ? `<small class="gold">${esc(rankName(d.adminLevel))}</small>` : ''}</h2>
                <div class="sub">${val(d.display)} · #${d.id} · registered ${fmtDate(d.created)}${d.online ? ` · <span class="good">online, ID ${d.online}</span>` : ''}</div></div></div>
            <div class="acc-tabs">${ACC_TABS.map(x => `<button data-tab="${x[0]}" class="${A.tab === x[0] ? 'on' : ''}">${x[1]}${
                x[0] === 'vehicles' ? ' ' + d.vehicles : x[0] === 'notes' && arr(d.notes).length ? ' ' + arr(d.notes).length : ''}</button>`).join('')}</div>
            <div class="acc-body">${body}</div>${actions}`;
        const tb = $('accTab');
        if (!tb) return;
        const sel = A.tabSel[A.tab];
        if (A.tab === 'stats') grid(tb, [{ key: 'name', label: 'Stat' }, { key: 'category', label: 'Category' }, { key: 'value', label: 'Value', cls: 'r', text: s => fmtInt(s.value) }], arr(t.list));
        else if (A.tab === 'vehicles') {
            grid(tb, [{ key: 'id', label: '#' }, { key: 'name', label: 'Model' }, { key: 'plate', label: 'Plate' },
                { key: 'state', label: 'Status', text: v => v.destroyed ? '<span class="bad">destroyed</span>' : v.spawned ? '<span class="good">spawned</span>' : '<span class="dim">garage</span>' }],
                arr(t.list), { sel: v => v.id === sel, click: v => { A.tabSel.vehicles = v.id; accDetail(); } });
            const v = arr(t.list).find(x => x.id === sel);
            tb.insertAdjacentHTML('beforeend', `<div class="acc-actions">${can('vehicles') ? '<button class="osa-btn" data-act="vehgive">Give vehicle</button>' : ''}
                ${v && v.destroyed && can('vehicles') ? '<button class="osa-btn" data-act="vehrestore">Restore</button>' : ''}
                ${v && can('vehicles') ? '<button class="osa-btn danger" data-act="vehdelete">Delete vehicle</button>' : ''}</div>`);
        } else if (A.tab === 'mails') {
            grid(tb, [{ key: 'ts', label: 'Date', text: m => fmtDate(m.ts) }, { key: 'kind', label: 'Kind' }, { key: 'subject', label: 'Subject' },
                { key: 'status', label: 'Status', text: m => `<span class="${m.status === 'sent' ? 'good' : m.status === 'failed' ? 'bad' : 'warn'}">${esc(m.status)}</span>` }],
                arr(t.list), { sel: m => A.mail && A.mail.id === m.id, click: async m => {
                    const r = await page('accounts', 'mail', { id: m.id }, true);
                    if (r.ok) { A.mail = r.result; accDetail(); }
                } });
            if (A.mail) tb.insertAdjacentHTML('beforeend', `<pre class="mail-view">${esc(A.mail.subject + '\n\n' + A.mail.body + (A.mail.error ? '\n\n[' + A.mail.error + ']' : ''))}</pre>`);
        } else if (A.tab === 'punishments') {
            tb.innerHTML = '<div class="secttl">Bans</div><div id="accBans"></div><div class="secttl">Admin actions</div><div id="accLog"></div>';
            grid($('accBans'), [{ key: 'at', label: 'Date', text: b => fmtDate(b.at) }, { key: 'reason', label: 'Reason' }, { key: 'admin', label: 'Admin' },
                { key: 'lifted', label: 'Status', text: b => b.lifted > 0 ? `<span class="dim">lifted by ${esc(b.liftedBy || '?')}</span>` : '<span class="bad">active</span>' }], arr(t.bans));
            grid($('accLog'), [{ key: 'ts', label: 'Date', text: l => fmtDate(l.ts) }, { key: 'admin', label: 'Admin' }, { key: 'action', label: 'Action' }], arr(t.log));
        } else if (A.tab === 'achievements') {
            grid(tb, [{ key: 'name', label: 'Achievement' }, { key: 'progress', label: 'Progress', cls: 'r', text: a => `${a.progress} / ${a.goal}` },
                { key: 'done', label: 'Unlocked', text: a => a.done ? `<span class="good">${fmtDate(a.at)}</span>` : '-' }],
                arr(t.list), { sel: a => a.id === sel, click: a => { A.tabSel.achievements = a.id; accDetail(); } });
            if (can('achievements')) tb.insertAdjacentHTML('beforeend', `<div class="acc-actions">${sel ? '<button class="osa-btn" data-act="achgive">Give</button><button class="osa-btn" data-act="achreset">Reset</button>' : ''}
                <button class="osa-btn danger" data-act="achresetall">Reset all</button></div>`);
        } else if (A.tab === 'inventory') {
            if (!t.online) tb.innerHTML = '<div class="osa-empty">The inventory is only readable while the player is online.</div>';
            else grid(tb, [{ key: 'name', label: 'Item', text: i => '&nbsp;'.repeat(i.depth * 4) + esc(i.name) }, { key: 'slot', label: 'Slot' }, { key: 'amount', label: 'Amount', cls: 'r' }], arr(t.list));
        } else if (A.tab === 'social') {
            tb.innerHTML = `<div class="kvt"><span>Crew</span><b>${val(t.crew)}</b></div><div class="secttl">Friends (${arr(t.friends).length})</div><div id="accFriends"></div>`;
            grid($('accFriends'), [{ key: 'name', label: 'Account' }], arr(t.friends).map(n => ({ name: n })), { click: f => accSelect(f.name) });
        } else if (A.tab === 'notes') {
            const notes = arr(d.notes).map((n, i) => Object.assign({ i: i + 1 }, n));
            grid(tb, [{ key: 't', label: 'Date', text: n => fmtDate(n.t) }, { key: 'admin', label: 'Admin' }, { key: 'text', label: 'Note', text: n => esc(n.text) }],
                notes, { sel: n => n.i === sel, click: n => { A.tabSel.notes = n.i; accDetail(); }, empty: 'No notes.' });
            if (sel && can('notes')) tb.insertAdjacentHTML('beforeend', '<div class="acc-actions"><button class="osa-btn danger" data-act="delnote">Delete note</button></div>');
        }
    }

    $('accDetail').addEventListener('click', async e => {
        const tabBtn = e.target.closest('.acc-tabs button');
        if (tabBtn) {
            A.tab = tabBtn.dataset.tab;
            A.mail = null;
            if (A.tab !== 'overview' && A.tab !== 'notes' && !A.tabData[A.tab]) accLoadTab(A.tab);
            return accDetail();
        }
        const wx = e.target.closest('button[data-workxp]');
        if (wx) return accAsk('workxp', 'Set work XP', 'XP', wx.dataset.xp, { work: wx.dataset.workxp }, true);
        const b = e.target.closest('button[data-act]');
        if (!b) return;
        const d = A.detail, act = b.dataset.act, sel = A.tabSel[A.tab];
        const reload = tab => setTimeout(() => accLoadTab(tab), 400);
        if (act === 'goto') return act && actGoto(d.online);
        if (act === 'setlevel') {
            const max = S.info.maxLevel, maxGrant = S.level >= max ? max : S.level - 1;
            const r = b.getBoundingClientRect();
            const items = [{ header: `Admin level of ${d.name}` }];
            for (let l = 0; l <= max; l++) items.push({ label: `${l}  ${rankName(l)}${l === d.adminLevel ? '  (current)' : ''}`, disabled: l > maxGrant || l === d.adminLevel, action: () => accEdit('setlevel', { value: l }) });
            return OSA.ui.openMenu(r.left, r.bottom + 2, items);
        }
        if (act === 'money') return accAsk('money', 'Edit cash', 'Cash', d.money, null, true);
        if (act === 'bank') return accAsk('bank', 'Edit bank money', 'Bank', d.bank, null, true);
        if (act === 'level') return accAsk('level', 'Edit level', 'Level', d.level, null, true);
        if (act === 'xp') return accAsk('xp', 'Edit XP', 'XP', d.xp, null, true);
        if (act === 'ban') return accAsk('ban', `Ban account ${d.name}`, 'Reason');
        if (act === 'unban' || act === 'unmute') return accEdit(act);
        if (act === 'email') {
            const f = await OSA.ui.form(`E-mail of ${d.name}`, [{ name: 'v', label: 'New e-mail address (empty = remove)', type: 'text' }], 'Save',
                'The address must not belong to another account. The player gets no mail about the change.');
            if (f) accEdit('email', { value: f.v || '' });
            return;
        }
        if (act === 'pwreset') {
            if (!(await OSA.ui.confirm('Send password reset', `A reset code is mailed to the e-mail address of ${d.name}. With it the player sets a new password in the game (Forgot password > I already have a code).`, 'Send'))) return;
            return accEdit('pwreset');
        }
        if (act === 'mail') return setTab('mail', { recipients: [d.name] });
        if (act === 'note') return accAsk('note', 'Add note', 'Note');
        if (act === 'delnote') { A.tabSel.notes = null; return accEdit('delnote', { index: sel }); }
        if (act === 'vehgive') { await accAsk('vehgive', 'Give vehicle', 'Model ID or name'); return reload('vehicles'); }
        if (act === 'vehrestore') { await accEdit('vehrestore', { id: sel }); return reload('vehicles'); }
        if (act === 'vehdelete') {
            if (!(await OSA.ui.confirm('Delete vehicle', 'The vehicle is removed from the account for good.', 'Delete'))) return;
            A.tabSel.vehicles = null;
            await accEdit('vehdelete', { id: sel });
            return reload('vehicles');
        }
        if (act === 'achgive') { await accEdit('achgive', { id: sel }); return reload('achievements'); }
        if (act === 'achreset') { await accEdit('achreset', { id: sel }); return reload('achievements'); }
        if (act === 'achresetall') {
            if (!(await OSA.ui.confirm('Reset achievements', 'Every achievement of this account is reset.', 'Reset all'))) return;
            await accEdit('achreset', {});
            return reload('achievements');
        }
    });

    function actGoto(id) { return act('adminWebAction', 'goto', id); }

    PAGES.accounts = {
        show(name) {
            page('accounts', 'filters', {}, true).then(r => { if (r.ok) { A.filters = arr(r.result.list); accFilters(); } });
            accFilters();
            accConds();
            if (typeof name === 'string' && name) {
                A.args.search = name;
                A.args.page = 0;
                accFilters();
                A.sel = null;
                A.tab = 'overview';
                accSelect(name);
            }
            accList();
        },
        render() { /* the list changes on its own requests only */ },
    };

    /* ============================================================ bans */

    const B = { active: true, page: 0, search: '', data: null, sel: null };
    async function bansLoad() {
        const r = await page('bans', 'list', { active: B.active, page: B.page, search: B.search }, true);
        if (r.ok) B.data = r.result;
        bansRender();
    }
    function bansRender() {
        const d = B.data;
        grid($('bnRows'), [
            { key: 'at', label: 'Date', text: b => fmtDate(b.at) },
            { key: 'account', label: 'Account', text: b => `<b>${val(b.account)}</b>` },
            { key: 'reason', label: 'Reason' },
            { key: 'admin', label: 'Admin' },
            { key: 'lifted', label: 'Status', text: b => b.lifted > 0 ? `<span class="dim">lifted by ${esc(b.liftedBy || '?')}</span>` : '<span class="bad">active</span>' },
        ], d ? arr(d.rows) : [], { sel: b => b.id === B.sel, click: b => { B.sel = b.id; bansRender(); }, empty: d ? 'No bans.' : 'Loading...' });
        const sel = d && arr(d.rows).find(b => b.id === B.sel);
        $('bnPager').innerHTML = `<button class="osa-btn small" data-p="-1"${B.page > 0 ? '' : ' disabled'}>‹</button><span>${B.page + 1}</span>
            <button class="osa-btn small" data-p="1"${d && d.more ? '' : ' disabled'}>›</button><span class="grow"></span>
            ${sel ? `<span class="dim">Serial ${val(sel.serial)} · IP ${val(sel.ip)}</span>` : ''}
            ${sel && sel.account && can('accounts') ? '<button class="osa-btn small" data-open="1">Open account</button>' : ''}
            ${sel && sel.account && sel.lifted === 0 && can('ban') ? '<button class="osa-btn small primary" data-unban="1">Unban</button>' : ''}`;
        const fmtLeft = s => { const m = Math.floor(Math.max(0, s) / 60); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`; };
        const rows = [];
        for (const p of S.players) {
            if (p.muted) rows.push({ p, kind: 'muted', left: fmtLeft(p.muteLeft), reason: p.muteReason, admin: p.muteAdmin });
            if (p.jailed) rows.push({ p, kind: 'jailed', left: p.jailLeft + 'm', reason: p.jailReason, admin: p.jailAdmin });
        }
        grid($('bnOnline'), [
            { key: 'name', label: 'Player', text: r => `<b>${esc(r.p.name)}</b> (${r.p.id})` },
            { key: 'kind', label: 'Kind', text: r => `<span class="warn">${r.kind}</span>` },
            { key: 'left', label: 'Left' },
            { key: 'reason', label: 'Reason', text: r => `${esc(r.reason || '?')} <span class="dim">(${esc(r.admin || '?')})</span>` },
        ], rows, { empty: 'Nobody is muted or jailed.' });
    }
    $('bnPager').addEventListener('click', async e => {
        const b = e.target.closest('button');
        if (!b || b.disabled) return;
        const sel = B.data && arr(B.data.rows).find(x => x.id === B.sel);
        if (b.dataset.p) { B.page += Number(b.dataset.p); return bansLoad(); }
        if (b.dataset.open && sel) return setTab('accounts', sel.account);
        if (b.dataset.unban && sel) { await page('bans', 'unban', { name: sel.account }); bansLoad(); }
    });
    let bnTimer = null;
    $('bnSearch').addEventListener('input', e => { B.search = e.target.value.trim(); B.page = 0; clearTimeout(bnTimer); bnTimer = setTimeout(bansLoad, 400); });
    $('bnActive').addEventListener('click', () => { B.active = true; B.page = 0; $('bnActive').classList.add('active'); $('bnAll').classList.remove('active'); bansLoad(); });
    $('bnAll').addEventListener('click', () => { B.active = false; B.page = 0; $('bnAll').classList.add('active'); $('bnActive').classList.remove('active'); bansLoad(); });
    PAGES.bans = { show: bansLoad, render: bansRender };

    /* ============================================================ resources */

    const R = { list: null, mode: 'all' };
    async function resLoad() {
        const r = await page('resources', 'list', {}, true);
        if (r.ok) R.list = arr(r.result.list);
        resRender();
    }
    function resRender() {
        $('rsMode').innerHTML = [['all', 'All'], ['running', 'Running'], ['stopped', 'Stopped'], ['failed', 'Failed']]
            .map(m => `<button class="osa-btn${R.mode === m[0] ? ' active' : ''}" data-m="${m[0]}">${m[1]}</button>`).join('');
        const f = $('rsSearch').value.trim().toLowerCase();
        const rows = (R.list || []).filter(r => (!f || r.name.toLowerCase().includes(f) || r.group.toLowerCase().includes(f))
            && (R.mode === 'all' || (R.mode === 'running' && r.state === 'running') || (R.mode === 'stopped' && r.state === 'loaded') || (R.mode === 'failed' && r.state === 'failed to load')));
        const stateCls = { running: 'good', loaded: 'dim', 'failed to load': 'bad' };
        grid($('rsRows'), [
            { key: 'name', label: 'Resource', text: r => `<b>${esc(r.name)}</b>${r.protected ? ' <span class="dim">[protected]</span>' : ''}` },
            { key: 'group', label: 'Folder' },
            { key: 'state', label: 'State', text: r => `<span class="${stateCls[r.state] || 'warn'}">${esc(r.state)}</span>` },
            { key: 'act', label: '', cls: 'r', text: r => r.state !== 'running' ? `<button class="osa-btn small" data-a="start" data-n="${esc(r.name)}">Start</button>`
                : r.protected ? '' : `<button class="osa-btn small" data-a="restart" data-n="${esc(r.name)}">Restart</button> <button class="osa-btn small danger" data-a="stop" data-n="${esc(r.name)}">Stop</button>` },
        ], rows, { empty: R.list ? 'No resource matches.' : 'Loading...' });
    }
    $('rsMode').addEventListener('click', e => { const b = e.target.closest('button[data-m]'); if (b) { R.mode = b.dataset.m; resRender(); } });
    $('rsSearch').addEventListener('input', resRender);
    $('rsReload').addEventListener('click', resLoad);
    $('rsRows').addEventListener('click', async e => {
        const b = e.target.closest('button[data-a]');
        if (!b) return;
        e.stopPropagation();
        if (b.dataset.a === 'stop' && !(await OSA.ui.confirm('Stop resource', `Stop ${b.dataset.n}?`, 'Stop'))) return;
        await page('resources', 'action', { name: b.dataset.n, action: b.dataset.a });
        setTimeout(resLoad, 800);
    }, true);
    // GitHub update check / update of v_main (checkupdates, updateresources)
    const U = { report: null, which: 'check', view: false, timer: null };
    async function updLoad() {
        const r = await page('resources', 'updates', {}, true);
        if (r.ok) U.report = r.result;
        updRender();
        clearTimeout(U.timer);
        if (U.view && S.tab === 'resources' && U.report && (U.report.checkRunning || U.report.updateRunning)) U.timer = setTimeout(updLoad, 2500);
    }
    function updRender() {
        const r = U.report || {};
        const busy = r.checkRunning || r.updateRunning;
        $('rsCheck').disabled = !!busy;
        $('rsInstall').disabled = !!busy;
        $('rsWhich').innerHTML = [['check', 'Last check' + (r.checkRunning ? ' …' : '')], ['update', 'Last update' + (r.updateRunning ? ' …' : '')]]
            .map(w => `<button class="osa-btn${U.which === w[0] ? ' active' : ''}" data-w="${w[0]}">${w[1]}</button>`).join('');
        const rep = r[U.which];
        $('rsRunInfo').textContent = rep ? `${fmtDate(rep.at)} · ${rep.by} · ${arr(rep.lines).length} lines` : '';
        const cls = { outdated: 'warn', missing: 'bad', error: 'bad', complete: 'good', notinst: 'dim', loose: 'dim' };
        const hm = ts => { if (!ts) return '-'; const d = new Date(ts * 1000), p = n => String(n).padStart(2, '0'); return `${p(d.getHours())}:${p(d.getMinutes())}`; };
        grid($('rsLines'), [
            { key: 'time', label: 'Time', text: l => hm(l.time) },
            { key: 'event', label: 'Event', text: l => `<span class="${cls[l.event] || ''}">${esc(l.event || 'status')}</span>` },
            { key: 'text', label: 'Line' },
        ], rep ? arr(rep.lines) : [], { empty: U.report ? 'No run since the server started.' : 'Loading...' });
    }
    $('rsView').addEventListener('click', () => {
        U.view = !U.view;
        $('rsView').textContent = U.view ? 'Resources' : 'Updates';
        $('rsRows').hidden = U.view;
        $('rsUpd').hidden = !U.view;
        if (U.view) updLoad();
    });
    $('rsWhich').addEventListener('click', e => { const b = e.target.closest('button[data-w]'); if (b) { U.which = b.dataset.w; updRender(); } });
    $('rsCheck').addEventListener('click', async () => { await page('resources', 'checkupdates', {}); U.which = 'check'; setTimeout(updLoad, 800); });
    $('rsInstall').addEventListener('click', async () => {
        if (!(await OSA.ui.confirm('Install updates', 'Downloads every changed repo file and writes it over the local copy (v_main updateresources). Changed resources may need a restart.', 'Install'))) return;
        await page('resources', 'updateresources', {});
        U.which = 'update';
        setTimeout(updLoad, 800);
    });
    PAGES.resources = { show: () => { resLoad(); if (U.view) updLoad(); }, render: () => {} };

    /* ============================================================ admin log */

    const AL = { page: 0, data: null };
    async function alLoad() {
        const r = await page('adminlog', 'list', { page: AL.page, admin: $('alAdmin').value, target: $('alTarget').value, text: $('alText').value }, true);
        if (r.ok) AL.data = r.result;
        grid($('alRows'), [
            { key: 'ts', label: 'Date', text: l => fmtDate(l.ts) },
            { key: 'admin', label: 'Admin', text: l => `<b>${esc(l.admin)}</b>` },
            { key: 'level', label: 'Level', cls: 'r' },
            { key: 'source', label: 'From', text: l => `<span class="${l.source === 'web' ? 'gold' : 'dim'}">${esc(l.source)}</span>` },
            { key: 'action', label: 'Action' },
            { key: 'target', label: 'Target', text: l => l.target ? `<span class="gold">${esc(l.target)}</span>` : '-' },
        ], AL.data ? arr(AL.data.rows) : [], { empty: 'No admin actions.', click: l => { if (l.target && can('accounts')) setTab('accounts', l.target); } });
        $('alPager').innerHTML = `<button class="osa-btn small" data-p="-1"${AL.page > 0 ? '' : ' disabled'}>‹</button><span>${AL.page + 1}</span>
            <button class="osa-btn small" data-p="1"${AL.data && AL.data.more ? '' : ' disabled'}>›</button>`;
    }
    let alTimer = null;
    ['alAdmin', 'alTarget', 'alText'].forEach(id => $(id).addEventListener('input', () => { AL.page = 0; clearTimeout(alTimer); alTimer = setTimeout(alLoad, 400); }));
    $('alPager').addEventListener('click', e => { const b = e.target.closest('button[data-p]'); if (b && !b.disabled) { AL.page += Number(b.dataset.p); alLoad(); } });
    PAGES.adminlog = { show: () => { AL.page = 0; alLoad(); }, render: () => {} };

    /* ============================================================ weekly */

    const W = { data: null, week: 0, tab: 'jobs' };
    async function wkLoad() {
        const r = await page('weekly', 'overview', {}, true);
        if (r.ok) W.data = r.result;
        wkRender();
    }
    async function wkEdit(action, a, b, c) {
        const w = W.data.weeks[W.week];
        const r = await page('weekly', 'edit', { action, offset: w.offset, a, b, c });
        if (r.result) W.data = r.result;
        wkRender();
    }
    function wkRender() {
        const d = W.data;
        if (!d) { $('wkBody').innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
        W.week = Math.min(W.week, arr(d.weeks).length - 1);
        const label = w => w.offset === 0 ? 'This week' : w.offset === 1 ? 'Next week' : `In ${w.offset} weeks`;
        $('wkWeeks').innerHTML = `<p class="dim">Next change: ${esc(d.nextChange)} UTC</p>` + arr(d.weeks).map((w, i) =>
            `<button class="wk-week${i === W.week ? ' on' : ''}" data-w="${i}"><b>${label(w)}</b><small>${esc(w.from)}${w.inherited ? ' (inherited)' : ''}</small></button>`).join('')
            + '<span class="grow"></span><button class="osa-btn danger" id="wkReset">Reset week (inherit previous)</button>';
        const w = d.weeks[W.week];
        const tabs = [['jobs', 'Job multipliers'], ['trial', 'Time trial'], ['login', 'Login bonus'], ['news', 'Weekly news']];
        let html = `<div class="osa-tabs">${tabs.map(t => `<button class="osa-tab${W.tab === t[0] ? ' active' : ''}" data-t="${t[0]}">${t[1]}</button>`).join('')}</div><div id="wkTab"></div>`;
        $('wkBody').innerHTML = html;
        const el = $('wkTab');
        const mults = arr(d.multipliers);
        if (W.tab === 'jobs') {
            grid(el, [
                { key: 'name', label: 'Job', text: j => `<b>${esc(j.name)}</b>` },
                { key: 'money', label: 'Money', text: j => { const m = w.jobs[j.id]; const cur = m ? m.money : 1;
                    return `<span class="mult">${mults.map(x => `<button class="osa-btn small${cur === x ? ' active' : ''}" data-job="${esc(j.id)}" data-kind="money" data-x="${x}">${x}x</button>`).join('')}</span>`; } },
                { key: 'xp', label: 'XP', text: j => { const m = w.jobs[j.id]; const cur = m ? m.xp : 1;
                    return `<span class="mult">${mults.map(x => `<button class="osa-btn small${cur === x ? ' active' : ''}" data-job="${esc(j.id)}" data-kind="xp" data-x="${x}">${x}x</button>`).join('')}</span>`; } },
            ], arr(d.jobs), { empty: 'v_jobmanager has no official jobs.' });
        } else if (W.tab === 'trial') {
            grid(el, [
                { key: 'name', label: 'Time trial', text: t => `<b>${esc(t.name)}</b>` },
                { key: 'time', label: 'Limit', text: t => `${t.time || 0} s` },
                { key: 'reward', label: 'Reward', cls: 'r', text: t => `<span class="good">${money(t.reward)}</span>` },
                { key: 'sel', label: '', cls: 'r', text: t => w.timetrial === t.i ? '<span class="gold">active</span>' : `<button class="osa-btn small" data-trial="${t.i}">Select</button>` },
            ], arr(d.trials).map((t, i) => Object.assign({ i: i + 1 }, t)), { empty: 'v_timetrial is not running.' });
        } else if (W.tab === 'login') {
            const b = w.loginBonus || { money: 0, xp: 0 };
            el.innerHTML = `<div class="row left" style="margin-top:12px"><label>Money <input class="osa-input" id="wkMoney" type="number" min="0" value="${b.money}"></label>
                <label>XP <input class="osa-input" id="wkXp" type="number" min="0" value="${b.xp}"></label><button class="osa-btn primary" id="wkLogin">Save</button></div>
                <p class="dim">Paid once per ${esc(d.period)} to every player who logs in. Max ${money(d.maxMoney)} and ${fmtInt(d.maxXp)} XP.</p>`;
        } else {
            const n = w.news || { title: '', body: '' };
            el.innerHTML = `<label class="col" style="margin-top:12px">Title <input class="osa-input" id="wkTitle" maxlength="60" value="${esc(n.title)}"></label>
                <label class="col">Text <textarea class="osa-textarea" id="wkText" maxlength="600" rows="8">${esc(n.body)}</textarea></label>
                <div class="row"><span></span><button class="osa-btn primary" id="wkNews">Save</button></div>`;
        }
    }
    $('wkWeeks').addEventListener('click', async e => {
        const b = e.target.closest('button');
        if (!b) return;
        if (b.dataset.w) { W.week = Number(b.dataset.w); return wkRender(); }
        if (b.id === 'wkReset' && await OSA.ui.confirm('Reset week', 'The week loses its own settings and inherits the previous week.', 'Reset')) wkEdit('reset');
    });
    $('wkBody').addEventListener('click', e => {
        const b = e.target.closest('button');
        if (!b) return;
        const w = W.data.weeks[W.week];
        if (b.dataset.t) { W.tab = b.dataset.t; return wkRender(); }
        if (b.dataset.job) {
            const m = w.jobs[b.dataset.job] || { money: 1, xp: 1 };
            const x = Number(b.dataset.x);
            return wkEdit('job', b.dataset.job, b.dataset.kind === 'money' ? x : m.money, b.dataset.kind === 'xp' ? x : m.xp);
        }
        if (b.dataset.trial) return wkEdit('trial', Number(b.dataset.trial));
        if (b.id === 'wkLogin') return wkEdit('login', Number($('wkMoney').value) || 0, Number($('wkXp').value) || 0);
        if (b.id === 'wkNews') return wkEdit('news', $('wkTitle').value.trim(), $('wkText').value.trim());
    });
    PAGES.weekly = { show: wkLoad, render: () => {} };

    /* ============================================================ news */

    const N = { data: null, sel: null };
    function nwFill(a) {
        N.sel = a ? a.id : null;
        $('nwDate').value = a ? a.dateText : (N.data ? N.data.nowDate : '');
        $('nwTime').value = a ? a.timeText : (N.data ? N.data.nowTime : '');
        $('nwTitle').value = a ? a.title : '';
        $('nwBody').value = a ? a.body : '';
        $('nwAuthor').textContent = a ? `#${a.id} · ${a.author || '-'}` : 'New article';
        $('nwDelete').hidden = !a;
        nwCount();
        nwRows();
    }
    function nwCount() { $('nwCount').textContent = `${$('nwBody').value.length} / 4000 · a blank line starts a new paragraph`; }
    function nwRows() {
        grid($('nwRows'), [
            { key: 'dateText', label: 'Date', text: a => `<span class="${a.scheduled ? 'warn' : 'dim'}">${esc(a.dateText)}</span>` },
            { key: 'title', label: 'Title', text: a => `${a.scheduled ? '<span class="warn">[scheduled]</span> ' : ''}${esc(a.title)}` },
        ], N.data ? arr(N.data.list) : [], { sel: a => a.id === N.sel, click: a => nwFill(a), empty: 'No articles yet.' });
    }
    function nwSet(r) {
        if (!r) return;
        N.data = r;
        if (r.selected) nwFill(arr(r.list).find(a => a.id === r.selected));
        else nwRows();
    }
    $('nwNew').addEventListener('click', () => nwFill(null));
    $('nwNow').addEventListener('click', () => { $('nwDate').value = N.data.nowDate; $('nwTime').value = N.data.nowTime; });
    $('nwBody').addEventListener('input', nwCount);
    $('nwSave').addEventListener('click', async () => {
        const r = await page('news', 'save', { id: N.sel, dateText: $('nwDate').value, timeText: $('nwTime').value, title: $('nwTitle').value, body: $('nwBody').value });
        if (r.result) nwSet(r.result);
    });
    $('nwDelete').addEventListener('click', async () => {
        if (!N.sel || !(await OSA.ui.confirm('Delete article', 'The article disappears from the news.', 'Delete'))) return;
        const r = await page('news', 'delete', { id: N.sel });
        if (r.result) { N.data = r.result; nwFill(null); }
    });
    PAGES.news = {
        async show() {
            const r = await page('news', 'list', {}, true);
            if (r.ok) { N.data = r.result; if (!N.sel) nwFill(null); else nwRows(); }
        },
        render: () => {},
    };

    /* ============================================================ mail */

    const M = { tab: 'compose', names: null, configured: true, chosen: new Set(), mode: 'all', langs: [], lang: null, texts: {},
        hist: { page: 0, groups: null, more: false, group: null, mails: null, mailId: null }, status: null, testLang: 'en' };

    function mlSaveText() {
        if (!M.lang) return;
        M.texts[M.lang] = { subject: $('mlSubject').value, body: $('mlBody').value };
    }
    function mlLangs() {
        if (!M.langs.length) M.langs = S.info && arr(S.info.languages).length ? arr(S.info.languages) : [{ value: 'en', label: 'English' }];
        M.lang = M.lang || M.langs[0].value;
        $('mlLangs').innerHTML = M.langs.map(l => {
            const t = M.texts[l.value] || {};
            const st = t.subject && t.body ? 'done' : (t.subject || t.body ? 'partial' : '');
            return `<button class="osa-btn langbtn ${st}${M.lang === l.value ? ' active' : ''}" data-l="${l.value}">${esc(l.label)} (${l.value.toUpperCase()})</button>`;
        }).join('');
        const t = M.texts[M.lang] || { subject: '', body: '' };
        $('mlSubject').value = t.subject || '';
        $('mlBody').value = t.body || '';
        mlHint();
    }
    function mlHint() {
        $('mlHint').textContent = `{name} = the account name · ${$('mlBody').value.length} / 8000 · a blank line starts a new paragraph`
            + (M.configured ? ' · recipients without their language get English (or the first filled language)' : ' · MAIL IS NOT CONFIGURED (Brevo API key)');
        const n = M.mode === 'all' ? (M.names ? M.names.length : 0) : M.chosen.size;
        $('mlSend').textContent = `Send to ${n}`;
    }
    function mlNames() {
        const total = M.names ? M.names.length : 0;
        $('mlMode').innerHTML = `<button class="osa-btn${M.mode === 'all' ? ' active' : ''}" data-mode="all">All (${total})</button>
            <button class="osa-btn${M.mode === 'selected' ? ' active' : ''}" data-mode="selected">Selected (${M.chosen.size})</button>`;
        const f = $('mlSearch').value.trim().toLowerCase();
        const shown = (M.names || []).filter(n => !f || n.toLowerCase().includes(f)).slice(0, 1500);
        $('mlNames').innerHTML = !M.names ? '<div class="osa-empty">Loading...</div>' : shown.map(n => {
            const on = M.mode === 'all' || M.chosen.has(n);
            return `<div class="nm-row ${on ? 'on' : 'off'}" data-n="${esc(n)}">${on ? '☑' : '☐'} ${esc(n)}</div>`;
        }).join('') || '<div class="osa-empty">No account.</div>';
        mlHint();
        return shown;
    }
    $('mlMode').addEventListener('click', e => { const b = e.target.closest('button'); if (b) { M.mode = b.dataset.mode; mlNames(); } });
    $('mlSearch').addEventListener('input', mlNames);
    $('mlNames').addEventListener('click', e => {
        const r = e.target.closest('.nm-row');
        if (!r) return;
        const n = r.dataset.n;
        if (M.chosen.has(n)) M.chosen.delete(n); else M.chosen.add(n);
        M.mode = 'selected';
        mlNames();
    });
    $('mlSelShown').addEventListener('click', () => { for (const n of mlNames()) M.chosen.add(n); M.mode = 'selected'; mlNames(); });
    $('mlClear').addEventListener('click', () => { M.chosen.clear(); mlNames(); });
    $('mlLangs').addEventListener('click', e => { const b = e.target.closest('button[data-l]'); if (!b) return; mlSaveText(); M.lang = b.dataset.l; mlLangs(); });
    ['mlSubject', 'mlBody'].forEach(id => $(id).addEventListener('input', () => { mlSaveText(); mlHint(); }));
    ['mlSubject', 'mlBody'].forEach(id => $(id).addEventListener('change', mlLangs));
    async function mlSend(mode) {
        mlSaveText();
        if (mode !== 'test') {
            const n = mode === 'all' ? (M.names ? M.names.length : 0) : M.chosen.size;
            if (!(await OSA.ui.confirm('Send circular', `The mail goes to ${n} account(s), each in its own language.`, 'Send'))) return;
        }
        await page('mail', 'send', { mode, names: mode === 'selected' ? Array.from(M.chosen) : null, texts: M.texts });
    }
    $('mlSend').addEventListener('click', () => mlSend(M.mode));
    $('mlTest').addEventListener('click', () => mlSend('test'));

    async function mlHistory(p) {
        const h = M.hist;
        h.page = p; h.groups = null;
        mlHistRender();
        const r = await page('mail', 'history', { page: p }, true);
        if (r.ok) { h.groups = arr(r.result.groups); h.more = r.result.more; }
        mlHistRender();
    }
    function mlHistRender() {
        const h = M.hist;
        grid($('mlGroups'), [
            { key: 'date', label: 'Date' }, { key: 'kind', label: 'Kind' }, { key: 'subject', label: 'Subject' },
            { key: 'total', label: 'Sent', cls: 'r', text: g => `<span class="${g.failed > 0 ? 'bad' : g.waiting > 0 ? 'warn' : 'good'}">${g.sent} / ${g.total}</span>` },
        ], h.groups || [], { sel: g => g.key === h.group, empty: h.groups ? 'No mails yet.' : 'Loading...', click: async g => {
            h.group = g.key; h.mails = null; h.mailId = null;
            $('mlView').textContent = 'Select a mail';
            mlHistRender();
            const r = await page('mail', 'group', { key: g.key }, true);
            if (r.ok && h.group === g.key) { h.mails = arr(r.result.mails); mlHistRender(); }
        } });
        const selG = (h.groups || []).find(g => g.key === h.group);
        $('mlPager').innerHTML = `<button class="osa-btn small" data-p="-1"${h.page > 0 ? '' : ' disabled'}>‹</button><span>${h.page + 1}</span>
            <button class="osa-btn small" data-p="1"${h.more ? '' : ' disabled'}>›</button><span class="grow"></span>
            ${selG && selG.failed > 0 ? `<button class="osa-btn small primary" data-retry="1">Retry ${selG.failed} failed</button>` : ''}`;
        grid($('mlMails'), [
            { key: 'account', label: 'Account' }, { key: 'language', label: 'Lang' }, { key: 'date', label: 'Date' },
            { key: 'status', label: 'Status', text: m => `<span class="${m.status === 'sent' ? 'good' : m.status === 'failed' ? 'bad' : 'warn'}">${esc(m.status)}</span>` },
        ], h.mails || [], { sel: m => m.id === h.mailId, empty: h.group ? 'Loading...' : 'Select a group', click: async m => {
            h.mailId = m.id;
            mlHistRender();
            const r = await page('mail', 'mail', { id: m.id }, true);
            if (r.ok) { const x = r.result.mail; $('mlView').textContent = `${x.subject}\n\n${x.body || ''}${x.error ? '\n\n[' + x.error + ']' : ''}`; }
        } });
    }
    $('mlPager').addEventListener('click', async e => {
        const r = e.target.closest('button[data-retry]');
        if (r) {
            const key = M.hist.group;
            if (!key || !(await OSA.ui.confirm('Retry failed mails', 'The failed mails of this group are sent again to the current e-mail address of each account.', 'Retry'))) return;
            await page('mail', 'retry', { key });
            return setTimeout(() => mlHistory(M.hist.page), 1500);
        }
        const b = e.target.closest('button[data-p]');
        if (b && !b.disabled) mlHistory(M.hist.page + Number(b.dataset.p));
    });

    async function mlStatus() {
        const r = await page('mail', 'status', {}, true);
        if (r.ok) M.status = r.result;
        const s = M.status;
        if (!s) { $('mlUpdates').innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
        const kv = (l, v, cls) => `<div class="kvt"><span>${esc(l)}</span><b class="${cls || ''}">${esc(v)}</b></div>`;
        const last = s.lastRun;
        $('mlUpdates').innerHTML = `<div class="tilesgrid" style="grid-template-columns:repeat(3,1fr);max-width:1100px">
            ${kv('Brevo', s.configured ? 'configured' : 'NOT configured', s.configured ? 'good' : 'bad')}${kv('Queue', fmtInt(s.queued))}
            ${kv('Server instance', `#${s.instance} (weekly updates are sent by #${s.sendingInstance})`, s.isSender ? 'good' : 'warn')}
            ${kv('Next weekly update', fmtDate(s.nextRun))}${kv('Pending update mails', fmtInt(s.pending), s.pending > 0 ? 'warn' : '')}
            ${kv('Sent in 24 h', `${s.sent24h} / ${s.dailyLimit}`)}${kv('Failed in 24 h', fmtInt(s.failed24h), s.failed24h > 0 ? 'bad' : '')}
            ${kv('Last run', last ? `${last.sent}/${last.total} sent · ${last.failed} failed · ${last.waiting} waiting · ${last.skipped} skipped` : '-')}
        </div>
        <div class="osa-panel" style="max-width:1100px;margin-top:14px"><div class="osa-panel-head"><strong>Test the weekly update mail</strong></div><div class="card-body">
            <p class="dim">Sends the weekly update mail as it would go out now (news of the last days + the running week) to the e-mail address of your own account only. It is not a part of any run and does not count in the daily limit.</p>
            <div class="row left">${M.langs.map(l => `<button class="osa-btn${M.testLang === l.value ? ' active' : ''}" data-tl="${l.value}">${esc(l.label)}</button>`).join('')}
            <span class="grow"></span><button class="osa-btn primary" id="mlUpdTest">Send test update to my e-mail</button><button class="osa-btn" id="mlUpdReload">Reload</button></div>
        </div></div>`;
    }
    $('mlUpdates').addEventListener('click', async e => {
        const b = e.target.closest('button');
        if (!b) return;
        if (b.dataset.tl) { M.testLang = b.dataset.tl; return mlStatus(); }
        if (b.id === 'mlUpdTest') { await page('mail', 'updatetest', { lang: M.testLang }); return mlStatus(); }
        if (b.id === 'mlUpdReload') mlStatus();
    });

    function mlTab(t) {
        M.tab = t;
        $('mlTabs').querySelectorAll('.osa-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === t));
        $('mlCompose').hidden = t !== 'compose';
        $('mlHistory').hidden = t !== 'history';
        $('mlUpdates').hidden = t !== 'updates';
        if (t === 'history') mlHistory(0);
        if (t === 'updates') mlStatus();
    }
    $('mlTabs').addEventListener('click', e => { const b = e.target.closest('.osa-tab'); if (b) mlTab(b.dataset.tab); });

    PAGES.mail = {
        async show(arg) {
            if (arg && arr(arg.recipients).length) {
                M.chosen = new Set(arg.recipients);
                M.mode = 'selected';
                mlTab('compose');
            }
            mlLangs();
            mlNames();
            const r = await page('mail', 'recipients', {}, true);
            if (r.ok) {
                M.names = arr(r.result.names);
                M.configured = r.result.configured !== false;
                for (const n of Array.from(M.chosen)) if (!M.names.includes(n)) M.chosen.delete(n);
            }
            mlNames();
        },
        render: () => {},
    };

    /* ============================================================ achievements */

    const AC = { list: null, sel: null };
    function achRender() {
        grid($('achRows'), [
            { key: 'id', label: 'ID', text: a => `<span class="dim">${esc(a.id)}</span>` },
            { key: 'name', label: 'Achievement', text: a => `<b>${esc(a.name)}</b>` },
            { key: 'desc', label: 'Description' },
            { key: 'category', label: 'Category' },
            { key: 'goal', label: 'Goal', cls: 'r' },
            { key: 'xp', label: 'XP', cls: 'r', text: a => `<span class="warn">${a.xp}</span>` },
        ], AC.list || [], { sel: a => a.id === AC.sel, click: a => { AC.sel = a.id; achRender(); }, empty: AC.list ? 'No achievements.' : 'Loading...' });
        $('achSel').textContent = AC.sel ? `Selected: ${AC.sel}` : 'Select an achievement';
        $('achGive').disabled = !AC.sel || !can('achievements');
    }
    $('achGive').addEventListener('click', () => {
        const name = $('achAccount').value.trim();
        if (!AC.sel || !name) return OSA.toast('Select an achievement and enter an account name.');
        page('achievements', 'give', { name, id: AC.sel });
    });
    PAGES.achievements = {
        async show() {
            const r = await page('achievements', 'list', {}, true);
            if (r.ok) AC.list = arr(r.result.list);
            achRender();
        },
        render: () => {},
    };
})();
