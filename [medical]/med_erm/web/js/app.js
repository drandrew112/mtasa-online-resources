// Dispatcher console: polling, task / unit lists, drag & drop, context menus.
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const { esc, arr, clean } = ERM;

    const S = {
        units: [],
        tasks: [],
        closed: [],
        tab: 'active',
        selected: null,      // task id
        dragTask: null,      // task id being dragged
        picking: false,      // "+ New" waiting for a map click
        loaded: false,
    };

    const PRIO_COLOR = { 1: '#e5484d', 2: '#f76b15', 3: '#ffc53d', 4: '#3e9bff' };
    const STATUS_COLOR = { available: '#2ea043', enroute: '#da3633', onscene: '#3884f4', handover: '#e6be28' };

    const unitById = id => S.units.find(u => u.id === id);
    const taskById = id => S.tasks.find(t => t.id === id) || S.closed.find(t => t.id === id);
    const isActive = t => t && t.status !== 'closed';

    /* ============================================================ polling */

    let timer = null, inflight = false, again = false;

    function normaliseTask(t) {
        t.units = arr(t.units);
        t.responseLog = arr(t.responseLog);
        t.unitLog = arr(t.unitLog);
        return t;
    }

    async function poll() {
        if (inflight) { again = true; return; }
        inflight = true;
        clearTimeout(timer);
        try {
            const r = await ERM.call('ermGetState', ERM.chat.lastId());
            if (!ERM.token) {
                inflight = false;
                return;
            }
            if (r && r.error === 'unauthorized') {
                inflight = false;
                return lock();
            } else if (r && r.ok) {
                OSA.time.sync(r.time);
                S.units = arr(r.units).map(u => (u.members = arr(u.members), u.accounts = arr(u.accounts), u));
                S.tasks = arr(r.tasks).map(normaliseTask);
                S.closed = arr(r.closed).map(normaliseTask);
                ERM.chat.add(arr(r.messages), !S.loaded);
                renderAuto(r.auto);
                S.loaded = true;
                render();
            }
            $('conn').className = 'osa-conn ok';
            $('conn').title = 'Connected';
        } catch (e) {
            $('conn').className = 'osa-conn bad';
            $('conn').title = 'Disconnected: ' + e.message;
        }
        inflight = false;
        if (again) { again = false; return poll(); }
        if (ERM.token) timer = setTimeout(poll, 1000);
    }

    function refresh() { if (ERM.token) poll(); }

    /* ============================================================ login */

    // Session gone (expired / server restart): start over with a clean page.
    function lock() {
        if (!ERM.token) return;
        ERM.token = null;
        clearTimeout(timer);
        location.reload();
    }

    $('loginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const code = $('loginCode').value.trim();
        if (!code) return;
        $('loginBtn').disabled = true;
        $('loginError').textContent = '';
        try {
            const r = await ERM.call('ermLogin', code);
            if (r && r.ok) {
                ERM.token = r.token;
                $('loginCode').value = '';
                $('who').textContent = r.displayName;
                document.body.classList.remove('locked');
                poll();
            } else {
                $('loginError').textContent = (r && r.error) || 'Login failed.';
                $('loginCode').select();
            }
        } catch (err) {
            $('loginError').textContent = 'Server unreachable: ' + err.message;
        }
        $('loginBtn').disabled = false;
    });

    $('logoutBtn').addEventListener('click', async () => {
        try { await ERM.call('ermLogout'); } catch (e) { /* ignore */ }
        ERM.token = null;
        location.reload();
    });

    /* ============================================================ rendering */

    function sortTasks(list) {
        const rank = { unassigned: 0, prioritized: 1, assigned: 2 };
        return list.slice().sort((a, b) =>
            (rank[a.status] - rank[b.status])
            || (a.status === 'unassigned' ? b.id - a.id : 0)
            || ((a.priority || 9) - (b.priority || 9))
            || (a.id - b.id));
    }

    let lastTaskHtml = '', lastUnitHtml = '';

    function renderTasks() {
        const list = S.tab === 'active' ? sortTasks(S.tasks) : S.closed;
        let html;
        if (!list.length) {
            html = `<li class="osa-empty">${S.tab === 'active' ? 'No active tasks.' : 'No closed tasks yet.'}</li>`;
        } else {
            html = list.map(t => {
                const prio = t.priority ? `<span class="osa-badge p${t.priority}">P${t.priority}</span>` : '<span class="osa-badge">--</span>';
                const chips = t.status === 'closed'
                    ? `<div class="task-meta"><span>${esc(t.closeReason)}</span><span>${esc(t.closedLabel)}</span></div>`
                    : (t.units.length
                        ? `<div class="chips">${t.units.map(u => `<span class="osa-chip bg-${u.status} ${u.status}">${esc(u.callsign)}</span>`).join('')}</div>`
                        : '');
                return `<li class="task pr-${t.priority || 0} ${t.status}${t.id === S.selected ? ' selected' : ''}"
                            data-id="${t.id}" data-drag="${isActive(t) && t.priority ? '1' : '0'}">
                    <div class="task-top">
                        <span class="task-id">#${t.id}</span>${prio}
                        <span class="task-title">${esc(t.title)}</span>
                        <span class="osa-pill ${t.status}">${ERM.TASK_STATUS[t.status] || t.status}</span>
                    </div>
                    <div class="task-meta"><span>${esc(t.zone)}</span><span>${ERM.age(t.createdAt)}</span></div>
                    ${chips}
                </li>`;
            }).join('');
        }
        if (html !== lastTaskHtml && S.dragTask === null) {
            $('taskList').innerHTML = html;
            lastTaskHtml = html;
        }
        $('countActive').textContent = S.tasks.length;
        $('countClosed').textContent = S.closed.length;
    }

    function renderUnits() {
        const list = S.units.slice().sort((a, b) => a.callsign.localeCompare(b.callsign));
        let html;
        if (!list.length) {
            html = '<li class="osa-empty">No units on duty.<br>Crews sign in on the tablet (J) in an ambulance.</li>';
        } else {
            html = list.map(u => {
                let status = ERM.STATUS[u.status] || u.status;
                if (u.status === 'handover' && u.handoverEnds) status += ` ${Math.max(0, u.handoverEnds - ERM.now())}s`;
                const task = u.task ? `#${u.task} ${esc(u.taskTitle)}` : 'No task';
                return `<li class="unit ${u.status}" data-id="${u.id}">
                    <span class="unit-name">${esc(u.callsign)}<small>${esc(u.type)} · ${esc(u.plate)}</small></span>
                    <span class="unit-status">${status}</span>
                    <span class="unit-sub">${task}</span>
                    <span class="unit-sub">${esc(u.members.map(clean).join(', '))}</span>
                </li>`;
            }).join('');
        }
        if (html !== lastUnitHtml) {
            $('unitList').innerHTML = html;
            lastUnitHtml = html;
            if (S.dragTask !== null) markDropTargets();
        }
        $('countUnits').textContent = S.units.length;
    }

    function renderPriorityBar() {
        const t = S.tasks.find(x => x.id === S.selected);
        $('selInfo').innerHTML = t
            ? `<b>#${t.id}</b> ${esc(t.title)}`
            : 'Select a task to set its priority';
        document.querySelectorAll('.prio').forEach(b => {
            b.disabled = !t;
            b.classList.toggle('current', !!t && t.priority === Number(b.dataset.prio));
        });
    }

    function renderStats() {
        const count = s => S.units.filter(u => u.status === s).length;
        const tcount = s => S.tasks.filter(t => t.status === s).length;
        const stat = (label, n, color) => `<span class="osa-stat">${color ? `<i class="osa-dot" style="background:${color}"></i>` : ''}${label} <b>${n}</b></span>`;
        $('stats').innerHTML =
            stat('Units', S.units.length) +
            stat('Available', count('available'), STATUS_COLOR.available) +
            stat('En Route', count('enroute'), STATUS_COLOR.enroute) +
            stat('On Scene', count('onscene'), STATUS_COLOR.onscene) +
            stat('Handover', count('handover'), STATUS_COLOR.handover) +
            stat('Not assigned', tcount('unassigned'), '#e5484d') +
            stat('Prioritized', tcount('prioritized'), '#ffc53d') +
            stat('Assigned', tcount('assigned'), '#57d172');
    }

    // med_erm_auto on: badge in the top bar
    function renderAuto(auto) {
        const on = !!(auto && auto.available && auto.enabled);
        $('autoBadge').hidden = !on;
        document.body.classList.toggle('auto-on', on);
    }

    function render() {
        if (S.selected !== null && !taskById(S.selected)) S.selected = null;
        renderTasks();
        renderUnits();
        renderPriorityBar();
        renderStats();
        ERM.map.update(S.tasks, S.units, S.selected);
        ERM.chat.setChannels(S.units, S.tasks);
    }

    /* ============================================================ tooltips */

    function taskTip(id) {
        const t = taskById(id);
        if (!t) return '';
        const units = t.units.map(u => u.callsign).join(', ') || 'None';
        return `<h4>#${t.id} ${esc(t.title)}</h4>
            <p>Status: <b>${ERM.TASK_STATUS[t.status]}</b> · Priority: <b>${t.priority ? 'P' + t.priority : 'not set'}</b></p>
            <p>Location: <b>${esc(t.zone)}</b></p>
            ${t.caller ? `<p>Caller: <b>${esc(t.caller)}</b></p>` : ''}
            <p>Received: <b>${ERM.clock(t.createdAt)}</b> (${ERM.age(t.createdAt)} ago)</p>
            <p>Units: <b>${esc(units)}</b></p>
            ${t.description ? `<p>${esc(t.description)}</p>` : ''}
            <p style="color:var(--faint)">Right-click for actions</p>`;
    }

    function unitTip(id) {
        const u = unitById(id);
        if (!u) return '';
        return `<h4>${esc(u.callsign)} <small>${esc(u.type)}</small></h4>
            <p>Status: <b style="color:${STATUS_COLOR[u.status]}">${ERM.STATUS[u.status]}</b>${u.responding ? ' · lights & siren' : ''}</p>
            <p>Plate: <b>${esc(u.plate)}</b></p>
            <p>Crew: <b>${esc(u.members.map(clean).join(', '))}</b></p>
            <p>Task: <b>${u.task ? '#' + u.task + ' ' + esc(u.taskTitle) : 'None'}</b></p>
            <p>Location: <b>${esc(u.zone)}</b></p>
            <p>On duty since: <b>${ERM.clock(u.startedAt)}</b> · closed cases: <b>${u.closedTasks}</b></p>
            <p style="color:var(--faint)">Right-click for actions</p>`;
    }

    /* ============================================================ actions */

    function selectTask(id, scroll) {
        S.selected = id;
        render();
        if (scroll) {
            const li = $('taskList').querySelector(`[data-id="${id}"]`);
            li && li.scrollIntoView({ block: 'nearest' });
        }
    }

    async function setPriority(id, p) {
        if (await ERM.act('ermSetPriority', id, p)) ERM.toast(`Task #${id} set to P${p}`, true);
    }

    async function assign(taskId, unitId) {
        const u = unitById(unitId);
        if (await ERM.act('ermAssign', taskId, unitId)) ERM.toast(`${u ? u.callsign : 'Unit'} assigned to #${taskId}`, true);
    }

    async function unassign(taskId, unitId) {
        const u = unitById(unitId);
        if (await ERM.act('ermUnassign', taskId, unitId)) ERM.toast(`${u ? u.callsign : 'Unit'} released from #${taskId}`, true);
    }

    async function closeTask(id) {
        const r = await ERM.ui.form(`Close task #${id}`, [
            { name: 'reason', label: 'Reason (optional)', placeholder: 'e.g. Patient refused transport' },
        ], 'Close task', 'Assigned units are released and become available.');
        if (r && await ERM.act('ermCloseTask', id, r.reason)) ERM.toast(`Task #${id} closed`, true);
    }

    async function createTask(x, y) {
        const r = await ERM.ui.form('New task', [
            { name: 'title', label: 'Title', placeholder: 'e.g. Unconscious person' },
            { name: 'description', label: 'Description', type: 'textarea' },
            { name: 'caller', label: 'Caller (optional)' },
        ], 'Create task', `Location: ${Math.round(x)}, ${Math.round(y)}`);
        if (!r) return;
        const res = await ERM.act('ermCreateTask', r.title, r.description, x, y, r.caller);
        if (res) {
            ERM.toast(`Task #${res.id} created - set its priority`, true);
            S.selected = res.id;
        }
    }

    /* ============================================================ context menus */

    function taskMenu(e, id) {
        const t = taskById(id);
        if (!t) return;
        const items = [{ header: `Task #${t.id}` }];

        if (isActive(t)) {
            items.push({ header: 'Priority' });
            for (let p = 1; p <= 4; p++) {
                items.push({ label: `P${p}${t.priority === p ? '  ✓' : ''}`, dot: PRIO_COLOR[p], action: () => setPriority(id, p) });
            }

            items.push('sep', { header: 'Assign unit' });
            const free = S.units.filter(u => !u.task);
            if (!t.priority) items.push({ label: 'Set a priority first', disabled: true });
            else if (!free.length) items.push({ label: 'No free units', disabled: true });
            else free.forEach(u => items.push({
                label: `${u.callsign} (${u.type}) - ${ERM.STATUS[u.status]}`,
                dot: STATUS_COLOR[u.status],
                action: () => assign(id, u.id),
            }));

            if (t.units.length) {
                items.push('sep', { header: 'Assigned units' });
                t.units.forEach(u => items.push({ label: `Unassign ${u.callsign}`, dot: STATUS_COLOR[u.status], action: () => unassign(id, u.id) }));
            }

            items.push('sep',
                { label: 'Message assigned units', disabled: !t.units.length, action: () => ERM.chat.open('task:' + id) },
                { label: 'Center on map', action: () => ERM.map.focus(t.x, t.y) },
                'sep',
                { label: 'Close task', danger: true, action: () => closeTask(id) });
        } else {
            items.push({ label: 'Center on map', action: () => ERM.map.focus(t.x, t.y) });
        }
        ERM.ui.openMenu(e.clientX, e.clientY, items);
    }

    function unitMenu(e, id) {
        const u = unitById(id);
        if (!u) return;
        const items = [{ header: `${u.callsign} · ${ERM.STATUS[u.status]}` }];

        if (u.task) {
            items.push(
                { label: `Show task #${u.task}`, action: () => { S.tab = 'active'; syncTabs(); selectTask(u.task, true); } },
                { label: `Unassign from #${u.task}`, action: () => unassign(u.task, id) });
        } else {
            items.push({ header: 'Assign to task' });
            const tasks = sortTasks(S.tasks.filter(t => t.priority));
            if (!tasks.length) items.push({ label: 'No prioritized tasks', disabled: true });
            tasks.forEach(t => items.push({
                label: `#${t.id} P${t.priority} - ${t.title}`,
                dot: PRIO_COLOR[t.priority],
                action: () => assign(t.id, id),
            }));
        }

        items.push('sep',
            { label: 'Message unit', action: () => ERM.chat.open('unit:' + id) },
            { label: 'Center on map', action: () => ERM.map.focus(u.x, u.y) });
        ERM.ui.openMenu(e.clientX, e.clientY, items);
    }

    function mapMenu(e, x, y) {
        ERM.ui.openMenu(e.clientX, e.clientY, [
            { header: `${Math.round(x)}, ${Math.round(y)}` },
            { label: 'Create task here', action: () => createTask(x, y) },
            { label: 'Broadcast message', action: () => ERM.chat.open('broadcast') },
        ]);
    }

    function mapClick(x, y) {
        if (!S.picking) return;
        S.picking = false;
        $('map').style.cursor = '';
        createTask(x, y);
    }

    /* ============================================================ drag & drop */

    const canDrop = (unitId, taskId = S.dragTask) => {
        const u = unitById(unitId), t = S.tasks.find(x => x.id === taskId);
        return !!(u && t && !u.task);
    };

    // Pointer based (mousedown / move / up): HTML5 drag & drop is not available
    // in the in-game (ui_browser / CEF) version of this page.

    const unitIdOf = el => Number(el.dataset.unitId || el.dataset.id);

    function markDropTargets() {
        document.querySelectorAll('.unit[data-id]').forEach(el => {
            el.classList.toggle('drop-bad', S.dragTask !== null && !canDrop(unitIdOf(el)));
        });
    }

    function clearDrop() {
        S.dragTask = null;
        document.body.classList.remove('is-dragging');
        document.querySelectorAll('.drop-ok, .drop-bad, .dragging').forEach(el => el.classList.remove('drop-ok', 'drop-bad', 'dragging'));
    }

    // Unit labels on the map are drop targets too.
    function makeDropTarget(el, unitId) {
        el.dataset.unitId = unitId;
    }

    function unitAt(x, y) {
        const el = document.elementFromPoint(x, y);
        const target = el && el.closest('.unit[data-id], .unit-label[data-unit-id]');
        return target ? { el: target, id: unitIdOf(target) } : null;
    }

    let drag = null;          // { taskId, x, y, li, ghost, active, over }
    let suppressClick = false;

    function dragStart(e) {
        const li = e.target.closest('.task');
        if (e.button !== 0 || !li || li.dataset.drag !== '1') return;
        drag = { taskId: Number(li.dataset.id), x: e.clientX, y: e.clientY, li, active: false };
    }

    window.addEventListener('mousemove', e => {
        if (!drag) return;
        if (!drag.active) {
            if (Math.abs(e.clientX - drag.x) + Math.abs(e.clientY - drag.y) < 6) return;
            const t = S.tasks.find(x => x.id === drag.taskId);
            drag.active = true;
            S.dragTask = drag.taskId;
            drag.li.classList.add('dragging');
            drag.ghost = document.createElement('div');
            drag.ghost.className = 'drag-ghost';
            drag.ghost.textContent = t ? `#${t.id} ${t.title}` : `#${drag.taskId}`;
            document.body.appendChild(drag.ghost);
            document.body.classList.add('is-dragging');
            ERM.ui.hideTip();
            markDropTargets();
        }
        e.preventDefault();
        drag.ghost.style.left = e.clientX + 14 + 'px';
        drag.ghost.style.top = e.clientY + 10 + 'px';

        const hit = unitAt(e.clientX, e.clientY);
        const over = hit && canDrop(hit.id) ? hit.el : null;
        if (drag.over !== over) {
            drag.over && drag.over.classList.remove('drop-ok');
            over && over.classList.add('drop-ok');
            drag.over = over;
        }
    });

    window.addEventListener('mouseup', e => {
        if (!drag) return;
        const d = drag;
        drag = null;
        if (!d.active) return;
        d.ghost && d.ghost.remove();
        clearDrop();
        suppressClick = true;
        setTimeout(() => { suppressClick = false; }, 0);
        const hit = unitAt(e.clientX, e.clientY);
        if (hit && canDrop(hit.id, d.taskId)) assign(d.taskId, hit.id);
    });

    /* ============================================================ wiring */

    const taskList = $('taskList');
    taskList.addEventListener('mousedown', dragStart);
    taskList.addEventListener('click', e => {
        if (suppressClick) return;
        const li = e.target.closest('.task');
        if (li) selectTask(Number(li.dataset.id));
    });
    taskList.addEventListener('dblclick', e => {
        const li = e.target.closest('.task');
        const t = li && taskById(Number(li.dataset.id));
        if (t) ERM.map.focus(t.x, t.y, 0.8);
    });
    taskList.addEventListener('contextmenu', e => {
        const li = e.target.closest('.task');
        if (!li) return;
        e.preventDefault();
        taskMenu(e, Number(li.dataset.id));
    });

    const unitList = $('unitList');
    unitList.addEventListener('contextmenu', e => {
        const li = e.target.closest('.unit');
        if (!li) return;
        e.preventDefault();
        unitMenu(e, Number(li.dataset.id));
    });
    unitList.addEventListener('dblclick', e => {
        const li = e.target.closest('.unit');
        const u = li && unitById(Number(li.dataset.id));
        if (u) ERM.map.focus(u.x, u.y, 0.8);
    });

    document.querySelectorAll('.prio').forEach(b => b.addEventListener('click', () => {
        if (S.selected !== null) setPriority(S.selected, Number(b.dataset.prio));
    }));

    function syncTabs() {
        document.querySelectorAll('.osa-tab').forEach(x => x.classList.toggle('active', x.dataset.tab === S.tab));
        lastTaskHtml = '';
        renderTasks();
    }
    document.querySelectorAll('.osa-tab').forEach(b => b.addEventListener('click', () => { S.tab = b.dataset.tab; syncTabs(); }));

    $('newTaskBtn').addEventListener('click', () => {
        S.picking = true;
        $('map').style.cursor = 'crosshair';
        ERM.toast('Click on the map to place the new task (right-click also works).', true);
    });

    setInterval(() => {
        const d = new Date();
        $('clock').textContent = [d.getHours(), d.getMinutes(), d.getSeconds()].map(n => String(n).padStart(2, '0')).join(':');
    }, 1000);

    ERM.app = {
        refresh, taskTip, unitTip, taskMenu, unitMenu, mapMenu, mapClick,
        selectTask: id => selectTask(id, true),
        makeDropTarget, lock,
    };

    $('loginCode').focus();
})();
