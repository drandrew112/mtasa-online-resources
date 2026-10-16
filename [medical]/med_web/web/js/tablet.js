// Web tablet: the in-game unit tablet (Home / Active Case / Messages) for unit crew members,
// signed in with the game account (web/tablet.html).
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const { esc, arr, clean } = ERM;
    const api = OSA.api();

    const PRIO_COLOR = { 1: '#e5484d', 2: '#f76b15', 3: '#ffc53d', 4: '#3e9bff' };
    const STATUS_COLOR = { available: '#2ea043', enroute: '#da3633', onscene: '#3884f4', handover: '#e6be28' };
    const STATUS_LABEL = ERM.STATUS;

    $('tabletUser').focus();

    /* ============================================================ state */

    const T = {
        token: null,
        page: 'home',
        chan: 'dispatch',
        unit: null,
        task: null,
        inUnit: false,
        messages: [],
        lastMsg: 0,
        lastEvent: -1,
        unread: { dispatch: 0, case: 0 },
        loaded: false,
        timer: null,
        busy: false,
        sig: {},
    };

    const call = (fn, ...args) => api.call(fn, T.token, ...args);

    /* ============================================================ alert sound */

    // the same sound as the in-game tablet; the sign-in click unlocks audio in the browser
    let alertSound = null;
    function unlockAudio() {
        try {
            if (!alertSound) alertSound = new Audio('sounds/tablet_alert.mp3');
            alertSound.volume = 1;
        } catch (e) { alertSound = null; }
    }
    function playAlert() {
        if (!alertSound) return;
        try {
            alertSound.currentTime = 0;
            const p = alertSound.play();
            if (p && p.catch) p.catch(() => { /* blocked until the user interacts */ });
        } catch (e) { /* ignore */ }
    }

    /* ============================================================ login */

    function showLoginError(text) { $('tabletLoginError').textContent = text || ''; }

    $('tabletLoginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('tabletUser').value.trim(), pass = $('tabletPass').value;
        if (!user || !pass) return;
        unlockAudio();
        $('tabletLoginBtn').disabled = true;
        showLoginError('');
        try {
            const r = await api.call('ermTabletLogin', null, user, pass);
            if (r && r.ok) {
                T.token = r.token;
                $('tabletPass').value = '';
                $('tbWho').textContent = r.account;
                document.body.classList.remove('locked');
                showPage('home');
                poll();
            } else {
                showLoginError((r && r.error) || 'Login failed.');
                $('tabletPass').select();
            }
        } catch (err) {
            showLoginError('Server unreachable: ' + err.message);
        }
        $('tabletLoginBtn').disabled = false;
    });

    function leave() {
        T.token = null;
        clearTimeout(T.timer);
        location.reload();
    }

    $('tbLogout').addEventListener('click', async () => {
        try { await call('ermTabletLogout'); } catch (e) { /* ignore */ }
        leave();
    });

    $('tbEndShift').addEventListener('click', async () => {
        if (!await OSA.ui.confirm('End shift', 'Your unit will be signed out.', 'End shift')) return;
        act('ermTabletEndShift');
    });

    /* ============================================================ polling */

    async function poll() {
        if (!T.token || T.busy) return;
        T.busy = true;
        clearTimeout(T.timer);
        try {
            const r = await call('ermTabletState', T.lastMsg, T.lastEvent);
            if (!T.token) { T.busy = false; return; }
            if (r && r.error === 'unauthorized') { T.busy = false; return leave(); }
            if (r && r.ok) apply(r);
            $('tbConn').className = 'osa-conn ok';
            $('tbConn').title = 'Connected';
        } catch (e) {
            $('tbConn').className = 'osa-conn bad';
            $('tbConn').title = 'Disconnected: ' + e.message;
        }
        T.busy = false;
        if (T.token) T.timer = setTimeout(poll, 1000);
    }

    function apply(r) {
        OSA.time.sync(r.time);
        const wasInUnit = T.inUnit;
        T.inUnit = !!r.inUnit;
        T.unit = T.inUnit ? r.unit : null;
        T.task = T.inUnit && r.task ? r.task : null;
        if (T.unit) { T.unit.members = arr(T.unit.members); T.unit.closedTasks = arr(T.unit.closedTasks); }
        if (T.task) T.task.units = arr(T.task.units);

        if (!T.inUnit && wasInUnit) {
            // the shift ended: forget the old unit's messages
            T.messages = []; T.lastMsg = 0; T.unread = { dispatch: 0, case: 0 };
        }
        T.lastEvent = Math.max(T.lastEvent, r.lastEvent);

        const quiet = !T.loaded;
        for (const e of arr(r.events)) {
            ERM.toast(e.title + ': ' + e.text, true);
            if (e.alert) playAlert();
        }
        for (const m of arr(r.messages)) addMessage(m, quiet);
        T.loaded = true;
        render();
    }

    /* ============================================================ messages */

    function chanOf(m) { return m.channel === 'task' ? 'case' : 'dispatch'; }

    function addMessage(m, quiet) {
        T.messages.push(m);
        T.lastMsg = Math.max(T.lastMsg, m.id);
        while (T.messages.length > 200) T.messages.shift();
        if (quiet) return;
        const own = !m.fromDispatch && T.unit && m.fromUnit === T.unit.id;
        const chan = chanOf(m);
        if (own || (T.page === 'messages' && T.chan === chan)) return;
        T.unread[chan]++;
        ERM.toast(`${clean(m.from)}: ${m.text}`, true);
    }

    function renderMessages() {
        if (T.chan === 'case' && !T.task) T.chan = 'dispatch';
        if (T.page === 'messages') T.unread[T.chan] = 0;

        document.querySelectorAll('#tbChanTabs .osa-tab').forEach(b => {
            const chan = b.dataset.chan, n = T.unread[chan];
            b.classList.toggle('active', chan === T.chan);
            b.disabled = chan === 'case' && !T.task;
            if (chan === 'case') b.firstChild.textContent = T.task ? `Case #${T.task.id} ` : 'Case chat ';
            const badge = b.querySelector('b');
            badge.hidden = !n || chan === T.chan;
            badge.textContent = n;
        });
        $('tbChanInfo').textContent = T.chan === 'case'
            ? 'Case chat - every unit on the case and the dispatchers'
            : `Dispatch channel - ${T.unit.callsign}`;
        $('tbChatText').placeholder = T.chan === 'case' ? 'Write to the case chat...' : 'Write a message to dispatch...';

        const list = T.messages.filter(m => chanOf(m) === T.chan && (T.chan !== 'case' || (T.task && m.target === T.task.id)));
        const html = list.length ? list.map(m => {
            let tag, cls;
            if (m.fromDispatch) {
                tag = m.channel === 'broadcast' ? 'BROADCAST' : m.channel === 'task' ? 'DISPATCH' : 'DIRECT';
                cls = m.channel === 'broadcast' ? 'broadcast' : m.channel === 'task' ? 'task' : 'unit';
            } else if (m.fromUnit === T.unit.id) {
                tag = 'SENT'; cls = 'sent';
            } else {
                tag = 'UNIT'; cls = 'unit';
            }
            return `<div class="msg${m.fromDispatch ? ' incoming' : ''}">
                <div class="msg-head"><span class="msg-tag tag-${cls}"${cls === 'sent' ? ' style="background:#2ea043"' : ''}>${tag}</span>
                <b>${esc(clean(m.from))}</b><time>${esc(m.time)}</time></div>
                <div class="msg-text">${esc(m.text)}</div></div>`;
        }).join('') : '<div class="osa-empty">No messages yet.</div>';

        if (html !== T.sig.chat) {
            const log = $('tbChatLog');
            const near = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
            log.innerHTML = html;
            T.sig.chat = html;
            if (near || T.sig.chatFresh) log.scrollTop = log.scrollHeight;
            T.sig.chatFresh = false;
        }
    }

    document.querySelectorAll('#tbChanTabs .osa-tab').forEach(b => b.addEventListener('click', () => {
        if (b.disabled) return;
        T.chan = b.dataset.chan;
        T.sig.chatFresh = true;
        renderMessages();
    }));

    $('tbChatForm').addEventListener('submit', async e => {
        e.preventDefault();
        const text = $('tbChatText').value.trim();
        if (!text) return;
        const r = await act('ermTabletSendMessage', text, T.chan);
        if (r) { $('tbChatText').value = ''; T.sig.chatFresh = true; }
    });

    /* ============================================================ pages */

    function showPage(page) {
        T.page = page;
        T.sig.chatFresh = true;
        document.querySelectorAll('#tbNav .osa-tab').forEach(b => b.classList.toggle('active', b.dataset.page === page));
        render();
    }

    document.querySelectorAll('#tbNav .osa-tab').forEach(b => b.addEventListener('click', () => showPage(b.dataset.page)));

    function duration(sec) {
        sec = Math.max(0, Math.floor(sec));
        const p = n => String(n).padStart(2, '0');
        return sec >= 3600
            ? `${Math.floor(sec / 3600)}:${p(Math.floor(sec % 3600 / 60))}:${p(sec % 60)}`
            : `${p(Math.floor(sec / 60))}:${p(sec % 60)}`;
    }

    const prioBadge = p => p ? `<span class="osa-badge p${p}">P${p}</span>` : '<span class="osa-badge">--</span>';

    function distanceText(d) {
        return d >= 1000 ? (d / 1000).toFixed(2) + ' km' : Math.round(d) + ' m';
    }

    function setHtml(el, html, key) {
        if (T.sig[key] === html) return;
        T.sig[key] = html;
        el.innerHTML = html;
    }

    function renderHome() {
        const u = T.unit, t = T.task;
        const crew = u.members.map(m => clean(m.name)).join(', ');
        const now = OSA.time.now();
        let html = `<h2 class="tb-h">Home</h2>
            <div class="tb-sub">Shift since ${OSA.clock(u.startedAt)} (${duration(now - u.startedAt)}) &middot; Crew: ${esc(crew)}</div>
            <div class="tb-label">Active case</div>`;
        if (t) {
            html += `<div class="tb-card" id="tbOpenCase" style="border-left-color:${PRIO_COLOR[t.priority] || 'var(--faint)'}">
                ${prioBadge(t.priority)}
                <div class="grow"><div class="t">#${t.id}&nbsp; ${esc(t.title)}</div><div class="z">${esc(t.zone)}</div></div>
                <span class="osa-muted">Open &rsaquo;</span></div>`;
        } else {
            html += '<div class="tb-card none">No active case - waiting for dispatch</div>';
        }
        const closed = u.closedTasks.slice().reverse();
        html += `<div class="tb-label">Closed cases this shift (${closed.length})</div><div class="tb-list">`;
        html += closed.length ? closed.map(c => `<div class="tb-row">
            <span class="id">#${c.id}</span>${prioBadge(c.priority || 0)}
            <span class="grow">${esc(c.title)}</span><span class="dim">${esc(c.zone)}</span>
            <span class="dim">${OSA.clock(c.closedAt)}</span></div>`).join('')
            : '<div class="osa-empty">No closed cases yet.</div>';
        html += '</div>';
        setHtml($('tbHome'), html, 'home');
    }

    $('tbHome').addEventListener('click', e => { if (e.target.closest('#tbOpenCase')) showPage('case'); });

    function renderCase() {
        const u = T.unit, t = T.task, el = $('tbCase');
        if (!t) {
            setHtml(el, `<div class="tb-empty"><h2>No active case</h2>
                <p>You will be notified when dispatch assigns you a case.</p></div>`, 'caseEmpty');
            return;
        }
        const now = OSA.time.now();
        const handover = u.status === 'handover';
        let state;
        if (handover) {
            state = `<span style="color:${STATUS_COLOR.handover}">Handover in progress${u.handoverEnds > 0 ? ` (${Math.max(0, u.handoverEnds - now)}s)` : ''}</span>`;
        } else if (u.responding) {
            state = `<span style="color:${STATUS_COLOR.enroute}">Lights &amp; siren active (${duration(now - u.responseFrom)})</span>`;
        } else if (u.reachedScene) {
            state = `<span style="color:${STATUS_COLOR.onscene}">On scene</span>`;
        } else {
            state = '<span class="osa-muted">Awaiting response</span>';
        }
        const units = t.units.map(x => x.callsign).join(', ');
        const info = `<div class="tb-title-row">${prioBadge(t.priority)}<h2>#${t.id}&nbsp; ${esc(t.title)}</h2></div>
            <div class="tb-sub">${esc(t.zone)} &middot; ${distanceText(t.distance || 0)}</div>
            <div class="tb-grid">
                <div><label>Received</label><span>${OSA.clock(t.createdAt)} (${duration(now - t.createdAt)} ago)</span></div>
                <div><label>Caller</label><span>${esc(t.caller || '-')}</span></div>
                <div><label>Units</label><span>${esc(units)}</span></div>
            </div>
            <div class="tb-desc${t.description ? '' : ' empty'}">${esc(t.description || 'No description.')}</div>
            <div class="tb-state">${state}</div>`;
        const btns = `<div class="tb-btns">
                <button class="osa-btn enroute" data-act="start"${u.responding || handover ? ' disabled' : ''}>Start response</button>
                <button class="osa-btn" data-act="stop"${u.responding ? '' : ' disabled'}>End response</button>
                <button class="osa-btn" data-act="leave"${t.units.length > 1 && !handover ? '' : ' disabled'}>Leave case</button>
                <button class="osa-btn closecase" data-act="close"${handover ? ' disabled' : ''}>Close case</button>
            </div>`;
        if (!$('tbCaseInfo')) {
            el.innerHTML = '<div id="tbCaseInfo"></div><div id="tbCaseBtns"></div>';
            T.sig.caseInfo = T.sig.caseBtns = T.sig.caseEmpty = null;
            $('tbCaseBtns').addEventListener('click', e => {
                const b = e.target.closest('[data-act]');
                if (b && !b.disabled) caseButton(b.dataset.act);
            });
        }
        setHtml($('tbCaseInfo'), info, 'caseInfo');
        setHtml($('tbCaseBtns'), btns, 'caseBtns');
    }

    async function caseButton(action) {
        const t = T.task;
        if (!t) return;
        if (action === 'start' || action === 'stop') {
            await act('ermTabletCaseAction', action);
        } else if (action === 'leave') {
            if (await OSA.ui.confirm(`Leave case #${t.id}`, 'Your unit will be released from the case.', 'Leave case')) {
                await act('ermTabletLeaveCase');
            }
        } else if (action === 'close') {
            const f = await OSA.ui.form(`Close case #${t.id}`,
                [{ name: 'reason', label: 'Reason for closing the case', placeholder: 'False call, scene is unsafe, ...' }],
                'Close case');
            if (!f) return;
            if (f.reason.length < 3) { ERM.toast('Give a reason for closing the case.'); return; }
            await act('ermTabletCloseCase', f.reason);
        }
    }

    // Runs an API action, reports its error and refreshes.
    async function act(fn, ...args) {
        try {
            const r = await call(fn, ...args);
            if (r && r.error === 'unauthorized') { leave(); return null; }
            if (!r || r.ok === false) { ERM.toast((r && r.error) || 'Request failed'); return null; }
            poll();
            return r;
        } catch (e) {
            ERM.toast('Server unreachable: ' + e.message);
            return null;
        }
    }

    /* ============================================================ render */

    function render() {
        const inUnit = T.inUnit;
        $('tbNoUnit').hidden = inUnit;
        $('tbHome').hidden = !inUnit || T.page !== 'home';
        $('tbCase').hidden = !inUnit || T.page !== 'case';
        $('tbMessages').hidden = !inUnit || T.page !== 'messages';
        $('tbNav').hidden = !inUnit;
        $('tbEndShift').hidden = !inUnit;

        if (!inUnit) {
            $('tbTitle').textContent = 'EMS Unit Tablet';
            $('tbSub').textContent = 'Not in a unit';
            return;
        }
        const u = T.unit;
        $('tbTitle').textContent = u.callsign;
        $('tbSub').innerHTML = `<span style="color:${STATUS_COLOR[u.status] || 'inherit'}">${esc(STATUS_LABEL[u.status] || u.status)}</span>`;

        if (T.page === 'home') renderHome();
        else if (T.page === 'case') renderCase();
        else renderMessages();

        const total = T.unread.dispatch + T.unread.case;
        $('tbUnread').hidden = !total;
        $('tbUnread').textContent = total;
    }

    setInterval(() => {
        const d = new Date(), p = n => String(n).padStart(2, '0');
        $('tbClock').textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    }, 1000);
})();
