// Home page: journey planner + map, live departure boards, the operators and their lines, and
// the "become a railway worker" section.
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const esc = OSA.esc, arr = OSA.arr, hhmm = OSA.hhmm;
    const api = OSA.api();

    let site = null;            // ptGetSite answer
    let stops = [];             // every stop (global ids)
    let journeys = [];
    let selJourney = 0;
    let boardStop = null, boardKind = 'dep', board = null;
    let tracks = [];            // railway geometry, drawn faintly under the stops

    const stopById = id => stops.find(s => s.id === id);
    const modeColor = mode => mode === 'bus' ? '#2fbf6b' : '#ffb52e';

    /* ================================================================ map */
    const map = new OSA.Map($('map'), { maxZoom: 4, focusZoom: 0.8 });

    // layer 1: the rail network
    map.addLayer((ctx, m) => {
        const w = Math.max(1.5, Math.min(4, m.zoom * 6));
        ctx.lineJoin = 'round';
        for (const t of tracks) {
            if (!t.length) continue;
            ctx.beginPath();
            t.forEach((p, i) => {
                const [sx, sy] = m.toScreen(p[0], p[1]);
                if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
            });
            ctx.strokeStyle = 'rgba(0,0,0,.45)';
            ctx.lineWidth = w + 2;
            ctx.stroke();
            ctx.strokeStyle = 'rgba(255,181,46,.55)';
            ctx.lineWidth = w;
            ctx.stroke();
        }
    });

    // layer 2: the selected journey (stop to stop)
    map.addLayer((ctx, m) => {
        const j = journeys[selJourney];
        if (!j) return;
        for (const leg of arr(j.legs)) {
            const pts = [leg.from, ...arr(leg.via), leg.to];
            ctx.beginPath();
            pts.forEach((p, i) => {
                const [sx, sy] = m.toScreen(p.x, p.y);
                if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
            });
            ctx.setLineDash(leg.kind === 'walk' ? [4, 6] : []);
            ctx.strokeStyle = 'rgba(0,0,0,.6)';
            ctx.lineWidth = 8;
            ctx.stroke();
            ctx.strokeStyle = leg.kind === 'walk' ? '#cfd8e6' : (leg.color || modeColor(leg.mode));
            ctx.lineWidth = 5;
            ctx.stroke();
        }
        ctx.setLineDash([]);
    });

    function drawStops() {
        const keep = new Set();
        const j = journeys[selJourney];
        const onRoute = new Set();
        if (j) for (const l of arr(j.legs)) { onRoute.add(l.from.id); onRoute.add(l.to.id); arr(l.via).forEach(v => onRoute.add(v.id)); }
        const from = $('from').value, to = $('to').value;
        for (const s of stops) {
            const key = 'st:' + s.id;
            keep.add(key);
            const on = s.id === from || s.id === to;
            const cls = 'm stop ' + s.mode + (on ? ' on' : '') + (j && !onRoute.has(s.id) ? ' dim' : '');
            map.marker(key, s.x, s.y, cls, `<span class="lbl">${esc(s.name)}</span>`, ev => stopMenu(ev, s));
        }
        map.removeMissing('st:', keep);
    }

    function stopMenu(ev, s) {
        OSA.ui.openMenu(ev.clientX, ev.clientY, [
            { header: s.name },
            { label: 'Journey from here', action: () => { $('from').value = s.id; afterPick(); } },
            { label: 'Journey to here', action: () => { $('to').value = s.id; afterPick(); } },
            'sep',
            { label: 'Departures', action: () => { selectBoard(s.id); $('departures').scrollIntoView({ behavior: 'smooth' }); } },
        ]);
    }

    function fitStops(list) {
        list = list.filter(s => s && (s.x || s.y));
        if (list.length < 2) return false;
        const xs = list.map(s => s.x), ys = list.map(s => s.y);
        return map.fitBox(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys), 70);
    }
    map.opts.onFit = () => fitStops(stops);

    /* ================================================================ planner */
    function fillStopSelects() {
        // grouped by city, sorted by name
        const groups = {};
        for (const s of stops) (groups[s.city || 'Other'] = groups[s.city || 'Other'] || []).push(s);
        const html = '<option value="">Choose a stop...</option>' + Object.keys(groups).sort().map(city =>
            `<optgroup label="${esc(city)}">` +
            groups[city].sort((a, b) => a.name.localeCompare(b.name))
                .map(s => `<option value="${esc(s.id)}">${esc(s.name)}${s.mode !== 'rail' ? ' (' + esc(PT.modeName(s.mode)) + ')' : ''}</option>`).join('') +
            '</optgroup>').join('');
        for (const id of ['from', 'to']) {
            const el = $(id), v = el.value;
            el.innerHTML = html;
            if (stopById(v)) el.value = v;
        }
    }

    function afterPick() {
        drawStops();
        if ($('from').value && $('to').value && $('from').value !== $('to').value) search();
    }

    $('from').onchange = afterPick;
    $('to').onchange = afterPick;
    $('swap').onclick = () => {
        const a = $('from').value;
        $('from').value = $('to').value;
        $('to').value = a;
        afterPick();
    };

    let whenMode = 'now';
    $('whenTabs').addEventListener('click', ev => {
        const b = ev.target.closest('[data-when]');
        if (!b) return;
        whenMode = b.dataset.when;
        $('whenTabs').querySelectorAll('.osa-tab').forEach(t => t.classList.toggle('active', t === b));
        $('whenTime').disabled = whenMode === 'now';
        if (whenMode === 'at' && !$('whenTime').value) $('whenTime').value = hhmm(PT.nowSec() + 600);
    });

    $('planForm').addEventListener('submit', ev => { ev.preventDefault(); search(); });

    let searchSeq = 0;
    async function search() {
        const from = $('from').value, to = $('to').value;
        if (!from || !to) { $('results').innerHTML = '<p class="osa-muted">Choose where you start and where you go.</p>'; return; }
        if (from === to) { $('results').innerHTML = '<p class="osa-muted">Departure and destination are the same stop.</p>'; return; }
        const when = whenMode === 'at' && $('whenTime').value ? $('whenTime').value : null;
        const seq = ++searchSeq;
        $('go').disabled = true;
        $('results').innerHTML = '<p class="osa-muted">Searching...</p>';
        try {
            const r = await api.call('ptPlan', from, to, when);
            if (seq !== searchSeq) return;
            if (!r || !r.ok) {
                journeys = [];
                $('results').innerHTML = `<p class="osa-muted">${esc((r && r.error) || 'No answer from the server.')}</p>`;
            } else {
                journeys = arr(r.journeys);
                selJourney = 0;
                renderJourneys(r);
                if (journeys[0]) fitJourney(journeys[0]);
            }
        } catch (e) {
            if (seq === searchSeq) $('results').innerHTML = '<p class="osa-muted">Connection error - try again.</p>';
        } finally {
            if (seq === searchSeq) $('go').disabled = false;
        }
        drawStops();
        map.redraw();
    }

    function fitJourney(j) {
        const pts = [];
        for (const l of arr(j.legs)) pts.push(l.from, ...arr(l.via), l.to);
        fitStops(pts);
    }

    const dayOf = ts => site ? Math.floor((ts - (site.time - site.sec)) / 86400) : 0;
    const dayTag = ts => {
        const d = dayOf(ts);
        return d === 1 ? ' <span class="osa-badge info">tomorrow</span>' : (d > 1 ? ` <span class="osa-badge info">+${d} days</span>` : '');
    };

    function timeHtml(t, sched) {
        // expected time; the scheduled one struck through when it differs by a minute or more
        if (sched && Math.abs(t.ts - sched.ts) >= 60) {
            return `<span class="late">${hhmm(t.sec)}</span> <s class="osa-muted">${hhmm(sched.sec)}</s>`;
        }
        return hhmm(t.sec);
    }

    function legCode(l) {
        return l.number || l.line || '';
    }

    function renderJourneys(r) {
        if (!journeys.length) {
            $('results').innerHTML = `<p class="osa-muted">No connection from <b>${esc(r.from.name)}</b> to <b>${esc(r.to.name)}</b> in the next hours.</p>`;
            return;
        }
        let html = `<div class="pt-result-head"><span>${esc(r.from.name)} &rarr; ${esc(r.to.name)}</span>` +
            `<span>from ${hhmm(r.when.sec)}</span></div>`;
        journeys.forEach((j, n) => {
            const legs = arr(j.legs);
            const rides = legs.filter(l => l.kind === 'ride');
            const chips = legs.map(l => l.kind === 'walk' ? PT.chip('walk', l.minutes + ' min', 'Walk')
                : PT.chip(l.mode, legCode(l), l.operator + ' - ' + l.name)).join('<span class="sep">&rsaquo;</span>');
            const firstRide = rides[0];
            const leaveIn = firstRide && site ? Math.round((firstRide.dep.ts - OSA.time.now()) / 60) : null;
            const warns = [];
            for (const l of rides) if (l.delay >= 60) warns.push(`${esc(legCode(l))} is running ${Math.round(l.delay / 60)} min late`);
            legs.forEach((l, i) => {
                if (l.changeMinutes !== undefined && l.changeMinutes < 2) warns.push(`Tight change at ${esc(l.from.name)} (${l.changeMinutes} min)`);
                if (i > 0 && l.kind === 'ride' && legs[i - 1].kind === 'ride') {
                    const prev = legs[i - 1];
                    if (prev.delay > 0 && prev.delay / 60 > l.changeMinutes) warns.push(`The change at ${esc(l.from.name)} may be missed`);
                }
            });
            html += `<div class="pt-journey${n === selJourney ? ' sel' : ''}" data-j="${n}">
                <div class="pt-j-sum">
                    <div class="pt-j-times">${hhmm(j.dep.sec)}<span class="arrow">&rarr;</span>${hhmm(j.arr.sec)}${dayTag(j.dep.ts)}</div>
                    <div class="osa-muted">${leaveIn !== null ? (leaveIn <= 0 ? 'leaves now' : 'in ' + PT.duration(leaveIn)) : ''}</div>
                    <div class="pt-j-meta"><b>${PT.duration(j.minutes)}</b><br>${j.transfers ? j.transfers + (j.transfers > 1 ? ' changes' : ' change') : 'direct'}</div>
                    <div class="pt-j-chips">${chips}</div>
                    ${warns.length ? `<div class="pt-j-warn">&#x26A0; ${warns.join(' &middot; ')}</div>` : ''}
                </div>
                <div class="pt-j-legs">${legsHtml(legs)}</div>
            </div>`;
        });
        $('results').innerHTML = html;
    }

    function legsHtml(legs) {
        let html = '';
        legs.forEach((l, i) => {
            const last = i === legs.length - 1;
            if (l.kind === 'walk') {
                html += `<div class="pt-leg walk">
                    <div class="pt-leg-stop"><span class="t">${hhmm(l.dep.sec)}</span><span class="n">${esc(l.from.name)}</span></div>
                    <div class="pt-leg-ride">${PT.chip('walk', 'Walk')} ${l.minutes} min, about ${l.dist} m to ${esc(l.to.name)}</div>
                </div>`;
            } else {
                const via = arr(l.via);
                const d = l.delay >= 60 ? ` <span class="late">+${Math.round(l.delay / 60)} min</span>` : (l.status === 'active' ? ' <span class="ontime">on time</span>' : '');
                html += `<div class="pt-leg ${esc(l.mode)}" style="--leg:${esc(l.color || modeColor(l.mode))}">
                    <div class="pt-leg-stop"><span class="t">${timeHtml(l.dep, l.schedDep)}</span><span class="n">${esc(l.from.name)}</span></div>
                    <div class="pt-leg-ride">
                        ${PT.chip(l.mode, legCode(l))}<b>${esc(l.name || '')}</b> towards ${esc(l.headsign || '')}${d}
                        <div>${esc(l.operator || '')} &middot; ${l.stops} stop${l.stops > 1 ? 's' : ''} &middot; ${PT.duration((l.arr.ts - l.dep.ts) / 60)}</div>
                        ${via.length ? `<details><summary>${via.length} intermediate stop${via.length > 1 ? 's' : ''}</summary><ul>${via.map(v =>
                            `<li>${v.arr ? hhmm(v.arr.sec) + ' ' : ''}${esc(v.name)}</li>`).join('')}</ul></details>` : ''}
                    </div>
                    <div class="pt-leg-stop pt-leg-end"><span class="t">${timeHtml(l.arr, l.schedArr)}</span><span class="n">${esc(l.to.name)}</span></div>
                </div>`;
            }
            if (!last) {
                const next = legs[i + 1];
                if (l.kind === 'ride' && next.kind === 'ride') {
                    html += `<div class="pt-leg walk"><div class="pt-leg-ride">Change at ${esc(l.to.name)} &middot; ${next.changeMinutes} min</div></div>`;
                }
            } else if (l.kind === 'walk') {
                html += `<div class="pt-leg walk last"><div class="pt-leg-stop"><span class="t">${hhmm(l.arr.sec)}</span><span class="n">${esc(l.to.name)}</span></div></div>`;
            }
        });
        return html;
    }

    $('results').addEventListener('click', ev => {
        if (ev.target.closest('details')) return;
        const card = ev.target.closest('.pt-journey');
        if (!card) return;
        const n = +card.dataset.j;
        selJourney = n;
        $('results').querySelectorAll('.pt-journey').forEach(c => c.classList.toggle('sel', +c.dataset.j === n));
        fitJourney(journeys[n]);
        drawStops();
        map.redraw();
    });

    /* ================================================================ departures */
    function renderStopList() {
        $('stopList').innerHTML = stops.slice().sort((a, b) => (a.city + a.name).localeCompare(b.city + b.name)).map(s =>
            `<button type="button" data-stop="${esc(s.id)}" class="${s.id === boardStop ? 'on' : ''}">
                <span>${PT.chip(s.mode, '')} ${esc(s.name)}</span><small>${esc(s.city)}</small></button>`).join('')
            || '<p class="osa-muted">No stops - the operators are offline.</p>';
    }
    $('stopList').addEventListener('click', ev => {
        const b = ev.target.closest('[data-stop]');
        if (b) selectBoard(b.dataset.stop);
    });
    $('boardTabs').addEventListener('click', ev => {
        const b = ev.target.closest('[data-kind]');
        if (!b) return;
        boardKind = b.dataset.kind;
        $('boardTabs').querySelectorAll('.osa-tab').forEach(t => t.classList.toggle('active', t === b));
        renderBoard();
    });

    function selectBoard(id) {
        boardStop = id;
        board = null;
        renderStopList();
        renderBoard();
        loadBoard();
    }

    const STATE_LABEL = {
        boarding: ['boarding', 'ok'], platform: ['at platform', 'ok'],
        departed: ['departed', ''], arrived: ['arrived', ''],
        cancelled: ['cancelled', 'bad'], scheduled: ['scheduled', ''],
    };

    function renderBoard() {
        const s = stopById(boardStop);
        $('boardName').textContent = s ? s.name : '-';
        $('boardCity').innerHTML = s ? esc(s.city) + (s.mode === 'rail'
            ? ` &middot; <a href="${esc(PT.pageUrl('map', { station: s.local_id }))}">on the live map</a>` : '') : '';
        if (!s) { $('board').innerHTML = '<p class="osa-muted">Choose a stop.</p>'; return; }
        if (!board) { $('board').innerHTML = '<p class="osa-muted">Loading...</p>'; return; }
        const dep = boardKind === 'dep';
        const list = arr(dep ? board.departures : board.arrivals);
        if (!list.length) { $('board').innerHTML = `<p class="osa-muted">No ${dep ? 'departures' : 'arrivals'} in the next two hours.</p>`; return; }
        let html = `<table class="osa-table board"><thead><tr><th>Time</th><th>Line</th><th>${dep ? 'To' : 'From'}</th>` +
            `<th class="c">Track</th><th class="r">Status</th></tr></thead><tbody>`;
        for (const e of list) {
            const st = e.state || 'scheduled';
            const gone = st === 'departed' || st === 'arrived' || st === 'cancelled';
            const late = !gone && st !== 'scheduled' && (e.delay || 0) >= 60;
            const via = arr(e.via);
            const lbl = STATE_LABEL[st];
            let status = lbl ? `<span class="osa-badge ${lbl[1]}">${lbl[0]}</span>` : '';
            if (late) status += ` <span class="late">+${Math.round(e.delay / 60)} min</span>`;
            else if (!status) status = '<span class="ontime">on time</span>';
            html += `<tr class="${gone ? 'done' : ''}${st === 'cancelled' ? ' cancel' : ''}">
                <td class="time">${hhmm(e.time)}${late ? `<div class="late">${hhmm(e.time + e.delay)}</div>` : ''}</td>
                <td><span class="line">${esc(e.train || e.line || '')}</span><div class="meta">${esc(e.name || '')}</div></td>
                <td><div class="dest">${esc(dep ? e.to : e.from)}</div>${via.length ? `<div class="meta">via ${via.map(esc).join(', ')}</div>` : ''}</td>
                <td class="c"><span class="trk">${esc(e.track || '-')}</span></td>
                <td class="r">${status}</td>
            </tr>`;
        }
        $('board').innerHTML = html + '</tbody></table>';
    }

    async function loadBoard() {
        if (!boardStop) return;
        const id = boardStop;
        try {
            const r = await api.call('ptGetBoard', id);
            if (id !== boardStop) return;
            board = r && r.ok ? r.board : { departures: [], arrivals: [] };
            renderBoard();
        } catch (e) { /* next poll */ }
    }

    /* ================================================================ network */
    function renderOperators() {
        let html = '';
        for (const op of arr(site.lines)) {
            const prov = arr(site.providers).find(p => p.id === op.provider) || {};
            const lines = arr(op.lines);
            html += `<div class="pt-card">
                <div class="pt-op-head">${PT.chip(op.mode, PT.modeName(op.mode))}<h3>${esc(op.name)}</h3>
                    <span class="osa-badge ${op.online ? 'ok' : 'bad'}">${op.online ? 'running' : 'offline'}</span></div>`;
            if (!lines.length) {
                html += '<p class="osa-muted">No timetable data right now.</p>';
            } else {
                html += `<table class="osa-table pt-lines"><thead><tr><th>Line</th><th>Route</th><th class="r">Every</th></tr></thead><tbody>` +
                    lines.map(l => `<tr>
                        <td class="code"><span class="pt-mode ${esc(op.mode)}" style="background:${esc(prov.color || '')}">${esc(l.code)}</span> ${esc(l.id)}</td>
                        <td><b>${esc(l.name)}</b>: ${esc(l.from)} &rarr; ${esc(l.to)}<div class="stops">${arr(l.stops).map(esc).join(' &middot; ')}</div></td>
                        <td class="r">${l.headway ? l.headway + ' min' : '-'}</td></tr>`).join('') +
                    '</tbody></table>';
            }
            html += '</div>';
        }
        for (const s of arr(site.comingSoon)) {
            html += `<div class="pt-card pt-soon">${PT.chip(s.mode, PT.modeName(s.mode))}<b>${esc(s.name)}</b>
                <span>Coming soon. The journey planner will combine them with the trains automatically.</span></div>`;
        }
        $('operators').innerHTML = html || '<p class="osa-muted">No operators.</p>';
    }

    /* ================================================================ careers */
    const money = n => '$' + Math.round(n).toLocaleString('en-US');

    function renderCareers(c) {
        const rail = c && c.rail;
        const points = rail ? arr(rail.stations).map(s => esc(s.name)) : [];
        const where = points.length ? points.join(' or ') : 'a Sunline Rail station';
        $('steps').innerHTML = `
            <li><b>Go to the duty point</b><span>Find the train driver duty marker at ${where}.</span></li>
            <li><b>Start your duty</b><span>Step into the marker and pick an outfit. On duty you hold the railway role:
                you may take trains out of the depot${c && c.railwayRoleRequired ? ' (without it you cannot)' : ''}.</span></li>
            <li><b>Apply for a service at the depot</b><span>The station depot lists the services departing in the next
                15 minutes. Pick one - your train is assembled on the right track.</span></li>
            <li><b>Drive the timetable</b><span>Open the timetable in the cab, keep to the times, stop at every station and
                keep the doors open at least 15 seconds. Watch the signals and acknowledge the Sifa with <kbd>Space</kbd>.</span></li>
            <li><b>Get paid</b><span>When the last stop is served, the pay goes straight to your bank account and you earn
                experience for the next rank.</span></li>`;

        if (!rail) {
            $('careerInfo').innerHTML = '<h3>Pay and ranks</h3><p class="osa-muted">The train driver work is not available right now.</p>';
            return;
        }
        const pay = rail.pay || {};
        const base = pay.base || {};
        let rows = Object.keys(base).map(k => `<tr><td>Base pay, ${esc(k)} service</td><td>${money(base[k])}</td></tr>`).join('');
        if (pay.perStop) rows += `<tr><td>Every served stop</td><td>+${money(pay.perStop)}</td></tr>`;
        for (const p of arr(pay.punctual)) rows += `<tr><td>Punctuality bonus (arrival within ${Math.round(p.max / 60)} min)</td><td>+${money(p.amount)}</td></tr>`;
        if (pay.skipFine) rows += `<tr><td>Skipped stop</td><td class="late">-${money(pay.skipFine)}</td></tr>`;
        if (pay.earlyFine) rows += `<tr><td>Early departure</td><td class="late">-${money(pay.earlyFine)}</td></tr>`;
        $('careerInfo').innerHTML = `
            <div class="pt-live"><b>${rail.onDuty || 0}</b> driver${rail.onDuty === 1 ? '' : 's'} on duty right now</div>
            <h3>${esc(rail.name || 'Train driver')}</h3>
            <p class="osa-muted">${esc(rail.description || '')}</p>
            <table class="osa-table pt-pay"><tbody>${rows}</tbody></table>
            <h3 style="margin-top:14px">Ranks</h3>
            <div class="pt-levels">${arr(rail.levels).map(l => `<span class="osa-chip"><b>${l.level}</b>${esc(l.name)}</span>`).join('')}</div>
            <p class="osa-muted">Up to level ${rail.maxLevel || '-'}. Higher ranks unlock new outfits.</p>`;
    }

    async function loadCareers() {
        try { renderCareers(await api.call('ptGetCareers')); } catch (e) { renderCareers(null); }
    }

    /* ================================================================ loading */
    async function loadSite(first) {
        try {
            const r = await api.call('ptGetSite');
            if (!r || !r.ok) return;
            site = r;
            OSA.time.sync(r.time);
            PT.syncClock(r.sec);
            stops = arr(r.stops);
            fillStopSelects();
            renderOperators();
            if (!stopById(boardStop)) boardStop = stops.length ? stops[0].id : null;
            renderStopList();
            drawStops();
            if (first) {
                const q = new URLSearchParams(location.search);
                if (stopById(q.get('from'))) $('from').value = q.get('from');
                if (stopById(q.get('to'))) $('to').value = q.get('to');
                fitStops(stops);
                loadBoard();
                if ($('from').value && $('to').value) search();
            }
        } catch (e) {
            if (first) $('results').innerHTML = '<p class="osa-muted">The server does not answer - retrying...</p>';
        }
    }

    async function loadTracks() {
        try {
            const n = await api.call('ptRailNetwork');
            if (n && n.ok) { tracks = arr(n.tracks).map(t => arr(t.points)); map.redraw(); }
        } catch (e) { /* the map works without them */ }
    }

    function tick() {
        $('clock').textContent = hhmm(PT.nowSec());
    }

    loadSite(true);
    loadTracks();
    loadCareers();
    tick();
    setInterval(tick, 1000);
    setInterval(() => loadSite(false), 60000);
    setInterval(loadBoard, 10000);
    setInterval(loadCareers, 60000);
})();
