// Network map application: polls the state, draws trains / stations / signals, shows the
// selected train (left panel) and the station departure / arrival boards (right panel).
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const esc = RWWEB.esc, arr = RWWEB.arr, hhmm = RWWEB.hhmm;
    const POLL_MS = 2000;
    const BOARD_POLL_MS = 5000;
    const ASPECT_COLOR = ['#e5484d', '#f2c230', '#2fbf6b'];

    let net = null, state = null, boards = null;
    let selTrain = null, selStation = null, hoverStation = null, hoverTrain = null;
    let boardStation = null;   // station on the right panel (last selected, default the first)
    let serverOffset = 0;      // server seconds-of-day minus local
    let failures = 0;

    /* ---------------------------------------------------------------- helpers */
    const trainLabel = c => c.service ? c.service.trip : (c.label || 'Train ' + c.id);
    const stationName = id => {
        const s = net && arr(net.stations).find(s => s.id === id);
        return s ? s.name : id;
    };
    const nowSec = () => {
        const d = new Date();
        return d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + serverOffset;
    };

    function tripsAt(stationId) {
        if (!state) return [];
        return arr(state.trips).filter(t => arr(t.stops).some(s => s.station === stationId));
    }

    // consists that have something to do with the station (timetable)
    function trainsAt(stationId) {
        const ids = new Set();
        if (!state) return ids;
        for (const c of arr(state.consists)) {
            if (c.service && arr(c.service.stops).some(s => s.station === stationId)) ids.add(c.id);
        }
        for (const t of tripsAt(stationId)) if (t.consist) ids.add(t.consist);
        return ids;
    }

    /* ---------------------------------------------------------------- network */
    function drawNetwork() {
        RWMap.setTracks(arr(net.tracks).map(t => ({ id: t.id, closed: t.closed, points: arr(t.points) })));
        $('companyName').textContent = net.company || 'Sunline Rail';
        document.title = (net.company || 'Sunline Rail') + ' - Network map';

        const keep = new Set();
        for (const s of arr(net.stations)) {
            const key = 'st:' + s.id;
            keep.add(key);
            const m = RWMap.marker(key, s.x, s.y, 'm station', `<span class="lbl">${esc(s.name)}</span>`, () => selectStation(s.id));
            m.dataset.st = s.id;
            if (!m._hover) {
                m._hover = true;
                m.addEventListener('mouseenter', () => { hoverStation = s.id; renderHighlight(); renderBoard(); });
                m.addEventListener('mouseleave', () => { hoverStation = null; renderHighlight(); renderBoard(); });
            }
        }
        RWMap.removeMissing('st:', keep);

        const keepSw = new Set();
        for (const w of arr(net.switches)) {
            keepSw.add('sw:' + w.id);
            RWMap.marker('sw:' + w.id, w.x, w.y, 'm switch');
        }
        RWMap.removeMissing('sw:', keepSw);

        const keepSig = new Set();
        for (const g of arr(net.signals)) {
            keepSig.add('sg:' + g.id);
            RWMap.marker('sg:' + g.id, g.x, g.y, 'm signal');
        }
        RWMap.removeMissing('sg:', keepSig);

        const list = arr(net.stations);

        // station picker of the board panel
        if (!list.some(s => s.id === boardStation)) boardStation = list.length ? list[0].id : null;
        $('boardPick').innerHTML = list.map(s => `<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('');
        $('boardPick').value = boardStation || '';
        renderBoard();

        // frame the LS-SF line
        if (!drawNetwork._fitted) drawNetwork._fitted = fitNetwork();
    }

    function fitNetwork() {
        const st = arr(net && net.stations);
        if (st.length >= 2) {
            const xs = st.map(s => s.x), ys = st.map(s => s.y);
            return RWMap.fitBox(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys), 80);
        }
        return RWMap.fitBox(-2300, -2200, 2900, 2800, 40) && false;
    }

    /* ---------------------------------------------------------------- state */
    function render() {
        const consists = arr(state.consists);
        const keep = new Set();
        for (const c of consists) {
            const key = 'tr:' + c.id;
            keep.add(key);
            const cls = 'm train' + (c.service ? ' green' : '') + (selTrain === c.id ? ' sel' : '');
            const m = RWMap.marker(key, c.x, c.y, cls, esc(trainLabel(c)), () => selectTrain(c.id));
            if (!m._hover) {
                m._hover = true;
                m.addEventListener('mouseenter', () => { hoverTrain = c.id; renderTrain(); });
                m.addEventListener('mouseleave', () => { hoverTrain = null; renderTrain(); });
            }
        }
        RWMap.removeMissing('tr:', keep);

        const aspects = state.aspects || {};
        for (const g of arr(net && net.signals)) {
            const a = aspects[g.id] !== undefined ? aspects[g.id] : aspects[String(g.id)];
            const m = RWMap.marker('sg:' + g.id, g.x, g.y, 'm signal');
            m.style.background = ASPECT_COLOR[a] || '#777';
        }
        for (const w of arr(state.switches)) {
            const sw = arr(net && net.switches).find(s => s.id === w.id);
            if (sw) RWMap.marker('sw:' + w.id, sw.x, sw.y, 'm switch' + (w.state === 'reverse' ? ' reverse' : ''));
        }

        // header stats
        const inService = consists.filter(c => c.service);
        $('statTrains').textContent = consists.length;
        $('statService').textContent = inService.length;
        const delays = inService.map(c => c.service.delay || 0);
        $('statPunct').textContent = delays.length ? RWWEB.delay(delays.reduce((a, b) => a + b, 0) / delays.length).text : '-';

        // the selected train goes away -> the first one
        if (!consists.some(c => c.id === selTrain)) selTrain = consists.length ? consists[0].id : null;
        if (!consists.some(c => c.id === hoverTrain)) hoverTrain = null;
        renderTrainPick(consists);
        renderTrain();
        renderHighlight();
    }

    function renderHighlight() {
        const st = hoverStation || selStation;
        const related = st ? trainsAt(st) : null;
        for (const c of arr(state && state.consists)) {
            const cls = 'm train' + (c.service ? ' green' : '') + (selTrain === c.id ? ' sel' : '') +
                (related && !related.has(c.id) ? ' dim' : '');
            RWMap.marker('tr:' + c.id, c.x, c.y, cls);
        }
        document.querySelectorAll('.m.station').forEach(m => m.classList.toggle('sel', m.dataset.st === selStation));
    }

    /* ---------------------------------------------------------------- train panel */
    // options rebuilt only when the trains / labels change (an open dropdown stays open)
    function renderTrainPick(consists) {
        const pick = $('trainPick');
        const opts = consists.map(c => [c.id, trainLabel(c) + (c.service ? ' \u2192 ' + stationName(c.service.to) : '')]);
        const key = JSON.stringify(opts);
        if (pick._key !== key) {
            pick._key = key;
            pick.innerHTML = opts.length ? opts.map(o => `<option value="${o[0]}">${esc(o[1])}</option>`).join('')
                : '<option value="">No trains</option>';
        }
        pick.value = selTrain !== null ? String(selTrain) : '';
        pick.disabled = !opts.length;
    }

    // hovered train on the map (preview) or the selected one
    function renderTrain() {
        const id = hoverTrain !== null ? hoverTrain : selTrain;
        const c = state && id !== null && arr(state.consists).find(c => c.id === id);
        $('trainPanel').classList.toggle('preview', hoverTrain !== null && hoverTrain !== selTrain);
        if (!c) {
            $('trainTag').className = 'tag grey';
            $('trainName').textContent = 'Trains';
            $('trainSub').textContent = '';
            $('trainInfo').innerHTML = `<p class="muted">${state ? 'No trains on the network.' : 'Loading...'}</p>`;
            $('trainStops').innerHTML = '';
            return;
        }
        const s = c.service;
        $('trainTag').className = 'tag ' + (s ? 'green' : 'grey');
        $('trainName').textContent = trainLabel(c);
        $('trainSub').innerHTML = s ? esc(s.name) + ': ' + esc(stationName(s.from)) + ' &rarr; ' + esc(stationName(s.to))
            : 'No active timetable';

        let html = `<dl class="kv">
                <dt>Driver</dt><dd>${esc(c.driver || 'nobody')}</dd>
                <dt>Speed</dt><dd>${c.speed} km/h${c.moving ? '' : ' (standing)'}</dd>
                <dt>Locomotive</dt><dd>${esc(c.label || c.loco)}</dd>
                <dt>Composition</dt><dd>${c.carriages ? c.carriages + ' carriage(s), ' + c.seats + ' seats' : 'light engine'}</dd>
                <dt>Track</dt><dd>${esc(c.trackName)}</dd>`;
        if (s) {
            const d = RWWEB.delay(s.delay);
            html += `<dt>Delay</dt><dd class="${d.cls}">${d.text}</dd>`;
            if (s.doors) html += `<dt>Doors</dt><dd>${esc(s.doors)}</dd>`;
        }
        $('trainInfo').innerHTML = html + '</dl>';

        if (!s) { $('trainStops').innerHTML = '<p class="muted">No active timetable.</p>'; return; }
        html = `<table class="tt board"><thead><tr><th>Station</th><th>Arr</th><th>Dep</th><th class="r">Actual</th></tr></thead><tbody>`;
        arr(s.stops).forEach((st, i) => {
            const cls = st.state === 'done' || st.state === 'skipped' ? 'done' : (i + 1 === s.nextStop ? 'next' : '');
            let actual = '';
            const actArr = i > 0 ? st.actArr : undefined;     // origin: only the departure counts
            if (st.actDep || actArr) {
                const t = st.actDep || actArr;
                const d = RWWEB.delay(t - (st.actDep ? st.dep : st.arr));
                actual = `${hhmm(t)} <span class="${d.cls}">${d.text}</span>`;
            } else if (st.state === 'skipped') actual = '<span class="late">not served</span>';
            html += `<tr class="${cls}"><td class="dest">${esc(st.name || stationName(st.station))}</td>
                <td class="time">${st.arr !== undefined && i > 0 ? hhmm(st.arr) : ''}</td>
                <td class="time">${st.dep !== undefined && i < arr(s.stops).length - 1 ? hhmm(st.dep) : ''}</td>
                <td class="r">${actual}</td></tr>`;
        });
        $('trainStops').innerHTML = html + '</tbody></table>';
    }

    $('trainPick').onchange = e => { if (e.target.value !== '') selectTrain(+e.target.value, true); };

    /* ---------------------------------------------------------------- station boards */
    const STATE_LABEL = {
        boarding: ['boarding', 'green'], platform: ['at platform', 'green'],
        departed: ['departed', 'grey'], arrived: ['arrived', 'grey'],
        cancelled: ['cancelled', 'red'],
        scheduled: ['scheduled', 'grey'],
    };

    function boardRows(list, dep) {
        list = arr(list);
        if (!list.length) return `<p class="muted">No ${dep ? 'departures' : 'arrivals'} in the next two hours.</p>`;
        let html = `<table class="tt board"><thead><tr><th>Time</th><th>Train</th><th>${dep ? 'To' : 'From'}</th>` +
            `<th class="c">Track</th><th class="r">Status</th></tr></thead><tbody>`;
        for (const e of list) {
            const st = e.state || 'scheduled';
            const gone = st === 'departed' || st === 'arrived' || st === 'cancelled';
            const late = !gone && st !== 'scheduled' && (e.delay || 0) >= 60;
            const via = arr(e.via);
            const lbl = STATE_LABEL[st];
            let status = lbl ? `<span class="badge ${lbl[1]}">${lbl[0]}</span>` : '';
            if (late) status += ` <span class="late">+${Math.round(e.delay / 60)} min</span>`;
            else if (!status) status = '<span class="ontime">on time</span>';
            html += `<tr class="${gone ? 'done' : ''}${st === 'cancelled' ? ' cancel' : ''}">
                <td class="time">${hhmm(e.time)}${late ? `<div class="late">${hhmm(e.time + e.delay)}</div>` : ''}</td>
                <td><span class="line">${esc(e.line || '')}</span><div class="meta">${esc(e.train || '')}</div></td>
                <td><div class="dest">${esc(dep ? e.to : e.from)}</div>${via.length ? `<div class="meta">via ${via.map(esc).join(', ')}</div>` : ''}</td>
                <td class="c"><span class="trk">${esc(e.track || '-')}</span></td>
                <td class="r">${status}</td>
            </tr>`;
        }
        return html + '</tbody></table>';
    }

    // hovered station on the map (preview) or the selected one
    function renderBoard() {
        const id = hoverStation || boardStation;
        const s = net && arr(net.stations).find(s => s.id === id);
        $('boards').classList.toggle('preview', !!hoverStation && hoverStation !== boardStation);
        if (!s) {
            $('boardName').textContent = 'Stations';
            $('boardCity').textContent = '';
            $('depList').innerHTML = $('arrList').innerHTML = '<p class="muted">Timetable service offline.</p>';
            return;
        }
        $('boardName').textContent = s.name;
        $('boardCity').textContent = s.city || '';
        const b = boards && boards[id];
        if (!b) {
            $('depList').innerHTML = $('arrList').innerHTML = `<p class="muted">${boards ? 'No board data.' : 'Loading...'}</p>`;
            return;
        }
        $('depList').innerHTML = boardRows(b.departures, true);
        $('arrList').innerHTML = boardRows(b.arrivals, false);
    }

    $('boardPick').onchange = e => selectStation(e.target.value, true);

    function selectTrain(id, focus) {
        selTrain = id;
        const c = state && arr(state.consists).find(c => c.id === id);
        if (focus && c) RWMap.focus(c.x, c.y, 0.9);
        render();
    }

    function selectStation(id, focus) {
        selStation = selStation === id && !focus ? null : id;
        const s = net && arr(net.stations).find(s => s.id === id);
        if (focus && s) RWMap.focus(s.x, s.y, 0.9);
        if (selStation) { boardStation = selStation; $('boardPick').value = selStation; }
        renderBoard();
        renderHighlight();
    }

    RWMap.el.addEventListener('mapclick', () => {
        // clears the highlight; the board keeps the last station
        if (selStation) { selStation = null; renderHighlight(); }
    });
    // signals only when zoomed in
    RWMap.el.addEventListener('mapmove', () => {
        const z = parseFloat((document.getElementById('mapImg').style.transform.match(/scale\(([\d.]+)\)/) || [])[1] || 1);
        document.getElementById('markers').classList.toggle('far', z < 0.55);
    });
    $('zoomFit').onclick = fitNetwork;

    /* ---------------------------------------------------------------- polling */
    function tickClock() {
        $('clock').textContent = hhmm(nowSec());
    }

    async function loadNetwork() {
        try {
            const n = await RWWEB.call('rwGetNetwork');
            if (n && n.tracks) { net = n; drawNetwork(); }
        } catch (e) { /* retried by poll */ }
    }

    async function pollBoards() {
        try {
            const b = await RWWEB.call('rwGetBoards');
            if (b && b.ok) { boards = b.boards || {}; renderBoard(); }
        } catch (e) { /* the state poll shows the offline banner */ }
        setTimeout(pollBoards, BOARD_POLL_MS);
    }

    async function poll() {
        try {
            const s = await RWWEB.call('rwGetState');
            if (s && s.ok) {
                state = s;
                const d = new Date();
                serverOffset = s.time - (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds());
                if (!net) await loadNetwork();
                else if (!arr(net.stations).length || !arr(net.signals).length) loadNetwork();
                if (net && !drawNetwork._fitted) drawNetwork._fitted = fitNetwork();
                render();
                failures = 0;
                $('offline').hidden = true;
            }
        } catch (e) {
            failures++;
            if (failures > 1) $('offline').hidden = false;
        }
        setTimeout(poll, POLL_MS);
    }

    RWMap.init();
    loadNetwork().then(() => { poll(); pollBoards(); });
    tickClock();
    setInterval(tickClock, 1000);
})();
