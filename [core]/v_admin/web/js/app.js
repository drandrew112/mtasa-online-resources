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
        tab: 'players',
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

    /* ============================================================ tabs */

    function setTab(tab) {
        S.tab = tab;
        document.querySelectorAll('#nav .osa-tab').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
        document.querySelectorAll('.tab-page').forEach(p => { p.hidden = p.id !== 'page-' + tab; });
        render();
    }
    document.querySelectorAll('#nav .osa-tab').forEach(b => b.addEventListener('click', () => setTab(b.dataset.tab)));

    function render() {
        $('who').innerHTML = `<b>${esc(S.account)}</b> · ${esc(rankName(S.level))} (${S.level})`;
        $('cntPlayers').textContent = S.players.length;
        const waiting = S.reports.filter(r => r.status !== 'claimed').length;
        const cr = $('cntReports');
        cr.textContent = waiting || S.reports.length;
        cr.classList.toggle('has', waiting > 0);
        if (S.tab === 'players') renderPlayers();
        else if (S.tab === 'reports') renderReports();
        else if (S.tab === 'server') renderServer();
        else if (S.tab === 'commands') renderCommands();
    }

    /* ============================================================ players */

    const ACTIONS = [
        { group: 'General' },
        { id: 'goto', label: 'Go to', perm: 'teleport', needGame: true },
        { id: 'gethere', label: 'Bring here', perm: 'teleport', needGame: true },
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
})();
