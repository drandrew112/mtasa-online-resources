// sanandreascontrol.eu: home (live status), documents (Markdown reader), procedures (SID / STAR /
// GA lists from avi_nav) and the airspace map. Pages are switched by the hash: #/home, #/docs/<id>,
// #/procedures/<ICAO>, #/map.
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const esc = OSA.esc, arr = OSA.arr;
    const api = OSA.api();
    const STATUS_MS = 10000;
    const PROC_TYPES = [['STAR', 'Arrivals (STAR)'], ['SID', 'Departures (SID)'], ['GA', 'Go-around']];

    let docs = [], nav = null, status = null;
    let curDoc = null, curApt = null, shownProc = null;   // shownProc = { id, ident, fixes: [ids] }
    let map = null, mapFitted = false;
    const layers = { cta: true, tma: true, ctr: true, fix: true, navaid: true, final: false };

    // ------------------------------------------------------------------ routing
    // web_api puts a <base href="/avi_web/web/"> into the page (over HTTP and in game), so a plain
    // "#/docs" link would resolve to another address and leave the page. Navigation therefore never
    // uses href: elements carry data-go="<page>/<arg>", go() switches the page in place and only
    // rewrites the fragment of the current address (absolute, so the <base> does not apply).
    let curRoute = '';
    function go(path) {
        path = String(path || 'home').replace(/^#?\/?/, '');
        curRoute = path;
        try { history.replaceState(null, '', location.pathname + location.search + '#/' + path); } catch (e) { /* CEF without history */ }
        route(path);
    }
    function route(path) {
        const parts = path.split('/');
        const page = ['home', 'docs', 'procedures', 'map'].includes(parts[0]) ? parts[0] : 'home';
        document.querySelectorAll('.page').forEach(p => p.classList.toggle('active', p.id === 'page-' + page));
        document.querySelectorAll('#nav a').forEach(a => a.classList.toggle('active', a.dataset.page === page));
        if (page === 'docs') openDoc(parts[1] ? decodeURIComponent(parts[1]) : (curDoc || (docs[0] && docs[0].id)), parts[2]);
        if (page === 'procedures') showProcedures(parts[1] || curApt);
        if (page === 'map') showMap();
    }
    document.addEventListener('click', e => {
        const el = e.target.closest('[data-go]');
        if (!el) return;
        e.preventDefault();
        go(el.dataset.go);
    });
    window.SacGo = go;

    // ------------------------------------------------------------------ clock
    function tickClock() {
        const d = new Date(OSA.time.now() * 1000);
        $('clock').textContent = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
    }
    setInterval(tickClock, 1000);

    // ------------------------------------------------------------------ home
    const POS_TYPE = { CTR: 'Control', APP: 'Approach', TWR: 'Tower' };

    function renderStatus() {
        const s = status;
        if (!s) return;
        const positions = arr(s.positions), airports = arr(s.airports);
        const open = positions.filter(p => p.controller);
        $('kOnline').textContent = open.length;
        $('kAir').textContent = s.traffic.airborne;
        $('kGnd').textContent = s.traffic.ground;
        $('kWind').textContent = String(Math.round(s.wind.dir)).padStart(3, '0') + '° / ' + Math.round(s.wind.speed) + ' kt';

        // positions: centre first, then per airport
        const groups = [['San Andreas Control', positions.filter(p => p.type === 'CTR')]];
        for (const a of airports) groups.push([a.city || a.icao, positions.filter(p => p.airport === a.icao)]);
        $('positions').innerHTML = groups.map(([title, list]) => `
            <div class="pos-group"><h4>${esc(title)}</h4>
            ${list.map(p => `
                <div class="pos ${p.controller ? 'on' : ''}">
                    <i class="osa-dot"></i>
                    <span class="pos-id">${esc(p.id)}</span>
                    <span class="pos-name">${esc(p.name)}</span>
                    <span class="pos-ctl">${p.controller ? esc(OSA.clean(p.controller)) : 'closed'}</span>
                </div>`).join('')}
            </div>`).join('');

        $('airports').innerHTML = `<table class="osa-table apt-table"><thead><tr>
            <th>Airport</th><th class="c">ARR rwy</th><th class="c">DEP rwy</th>
            <th class="r">Inbound</th><th class="r">Outbound</th><th class="r">Ground</th></tr></thead><tbody>
            ${airports.map(a => `<tr>
                <td><b>${esc(a.icao)}</b> <span class="osa-muted">${esc(a.name || '')}</span></td>
                <td class="c"><span class="rwy">${esc(a.arr || '-')}</span></td>
                <td class="c"><span class="rwy">${esc(a.dep || '-')}</span></td>
                <td class="r">${a.arrivals}</td><td class="r">${a.departures}</td><td class="r">${a.ground}</td>
            </tr>`).join('')}</tbody></table>
            <p class="osa-muted small">${s.traffic.overflights} overflights in the FIR · elevation:
            ${airports.map(a => `${esc(a.icao)} ${Math.round(a.elevation)} ft`).join(', ')}</p>`;
    }

    function renderHomeDocs() {
        $('homeDocs').innerHTML = docs.length ? docs.map(d => `
            <a class="doc-card" data-go="docs/${esc(d.id)}">
                <span class="doc-code">${esc(d.code || '')}</span>
                <b>${esc(d.title)}</b>
                <span class="osa-muted">${esc(d.summary || '')}</span>
                <span class="doc-ver">v${esc(d.version || '1')} · ${esc(d.updated || '')}</span>
            </a>`).join('') : '<p class="osa-muted">No documents.</p>';
    }

    // ------------------------------------------------------------------ documents
    // The reader: library (categories, filter) on the left, the document as a sheet in the middle,
    // its contents under the library. Figures: jpg / png load as files, svg come from sacGetImage.
    let docFilter = '';
    const svgCache = {};

    function renderDocList() {
        const q = docFilter.trim().toLowerCase();
        const list = docs.filter(d => !q || [d.title, d.code, d.summary, d.category].join(' ').toLowerCase().includes(q));
        const cats = [];
        for (const d of list) if (!cats.includes(d.category || 'Other')) cats.push(d.category || 'Other');
        $('docList').innerHTML = (cats.map(c => `<div class="doc-cat">${esc(c)}</div>` +
            list.filter(d => (d.category || 'Other') === c).map(d =>
                `<a class="doc-link ${d.id === curDoc ? 'active' : ''}" data-go="docs/${esc(d.id)}">
                    ${esc(d.title)}<small>${esc(d.code || '')}</small></a>`).join('')).join(''))
            || '<p class="osa-muted small">No document matches.</p>';
    }
    $('docSearch').addEventListener('input', e => { docFilter = e.target.value; renderDocList(); });

    function scrollToId(id, smooth) {
        const el = id && document.getElementById(id);
        const box = $('docScroll');
        if (!el) return;
        const top = el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop - 12;
        box.scrollTo({ top, behavior: smooth === false ? 'auto' : 'smooth' });
    }

    async function fillFigures() {
        for (const el of $('docBody').querySelectorAll('.md-svg[data-svg]')) {
            const name = el.dataset.svg;
            if (!(name in svgCache)) {
                try { svgCache[name] = await api.call('sacGetImage', name); } catch (e) { svgCache[name] = false; }
            }
            el.innerHTML = svgCache[name] || '<p class="osa-muted">Figure not available.</p>';
        }
    }

    function docPager(id) {
        const i = docs.findIndex(d => d.id === id);
        const prev = docs[i - 1], next = docs[i + 1];
        return `<nav class="doc-pager">
            ${prev ? `<a data-go="docs/${esc(prev.id)}"><small>Previous</small>${esc(prev.title)}</a>` : '<span></span>'}
            ${next ? `<a class="next" data-go="docs/${esc(next.id)}"><small>Next</small>${esc(next.title)}</a>` : '<span></span>'}
        </nav>`;
    }

    async function openDoc(id, anchor) {
        if (!id) return;
        if (id === curDoc && $('docBody').dataset.loaded === id) { scrollToId(anchor); return; }
        curDoc = id;
        renderDocList();
        $('docBody').innerHTML = '<p class="osa-muted">Loading...</p>';
        $('docMeta').innerHTML = '';
        $('toc').innerHTML = '';
        $('docPager').innerHTML = '';
        let d;
        try { d = await api.call('sacGetDocument', id); } catch (e) { d = null; }
        if (curDoc !== id) return;      // another document was opened meanwhile
        if (!d) { $('docBody').innerHTML = '<p class="osa-muted">The document is not available.</p>'; return; }
        const r = SacMarkdown.render(d.text);
        $('docMeta').innerHTML = `<span>${esc(d.code || '')}</span><span>Version ${esc(d.version || '1')}</span>
            <span>Updated ${esc(d.updated || '')}</span><span>${esc(d.category || '')}</span>`;
        $('docBody').innerHTML = r.html;
        $('docBody').dataset.loaded = id;
        $('docPager').innerHTML = docPager(id);
        $('toc').innerHTML = r.toc.map(t => `<a class="lv${t.level}" data-id="${t.id}">${esc(t.text)}</a>`).join('');
        $('docScroll').scrollTop = 0;
        await fillFigures();
        if (anchor) scrollToId(anchor, false);
    }

    // contents and in-document links scroll; they never change the address
    $('toc').addEventListener('click', e => {
        const a = e.target.closest('a[data-id]');
        if (a) scrollToId(a.dataset.id);
    });
    $('docBody').addEventListener('click', e => {
        const a = e.target.closest('a[data-anchor]');
        if (a) { e.preventDefault(); scrollToId(a.dataset.anchor); return; }
        const img = e.target.closest('.md-fig img, .md-fig .md-svg');
        if (img) openLightbox(img);
    });

    // figure enlarged over the page (screenshots are small in the sheet)
    function openLightbox(el) {
        const box = $('lightbox');
        const fig = el.closest('figure');
        const cap = fig && fig.querySelector('figcaption');
        $('lightboxBody').innerHTML = el.tagName === 'IMG' ? `<img src="${el.getAttribute('src')}" alt="">` : el.innerHTML;
        $('lightboxCap').innerHTML = cap ? cap.innerHTML : '';
        box.classList.add('open');
    }
    $('lightbox').addEventListener('click', () => $('lightbox').classList.remove('open'));
    document.addEventListener('keydown', e => { if (e.key === 'Escape') $('lightbox').classList.remove('open'); });

    // ------------------------------------------------------------------ procedures
    const point = id => nav && nav.byId[id];

    function showProcedures(icao) {
        if (!nav) return;
        const airports = nav.airports;
        if (!airports.length) { $('procBody').innerHTML = '<p class="osa-muted">No airports.</p>'; return; }
        curApt = airports.some(a => a.icao === icao) ? icao : airports[0].icao;
        $('aptTabs').innerHTML = airports.map(a =>
            `<a class="osa-tab ${a.icao === curApt ? 'active' : ''}" data-go="procedures/${esc(a.icao)}">${esc(a.icao)} <b>${esc(a.city || '')}</b></a>`).join('');
        const apt = airports.find(a => a.icao === curApt);
        const rwys = arr(apt.runways);
        const st = status && arr(status.airports).find(a => a.icao === curApt);

        let html = `<section class="card"><h2>${esc(apt.name)} <span class="osa-muted">${esc(apt.icao)} · elevation ${Math.round(apt.elevation)} ft</span></h2>
            <table class="osa-table"><thead><tr><th>Runway</th><th>Use</th><th>Ends (heading · final fix)</th></tr></thead><tbody>
            ${rwys.map(rw => `<tr><td><b>${esc(rw.id)}</b></td><td>${esc({ arr: 'arrivals', dep: 'departures', both: 'arrivals + departures' }[rw.use] || rw.use || '')}</td>
                <td>${arr(rw.ends).map(e => `<span class="rwy ${st && (st.arr === e.ident || st.dep === e.ident) ? 'in-use' : ''}">${esc(e.ident)}</span>
                    ${Math.round(e.hdg)}° · ${esc(e.final || '-')}`).join(' &nbsp; ')}</td></tr>`).join('')}
            </tbody></table>
            ${st ? `<p class="osa-muted small">In use now: arrivals <b>${esc(st.arr || '-')}</b>, departures <b>${esc(st.dep || '-')}</b>. Highlighted ends are in use.</p>` : ''}
            </section>`;

        for (const [type, title] of PROC_TYPES) {
            const list = nav.procedures.filter(p => p.airport === curApt && p.type === type);
            if (!list.length) continue;
            html += `<section class="card"><h2>${title}</h2><table class="osa-table proc-table"><thead><tr>
                <th>Procedure</th><th>Runway</th><th>Route</th><th></th></tr></thead><tbody>`;
            for (const p of list) {
                const runways = Object.keys(p.runways || {}).sort();
                runways.forEach((ident, i) => {
                    const fixes = arr(p.runways[ident]);
                    const sel = shownProc && shownProc.id === p.id && shownProc.ident === ident;
                    html += `<tr class="${i === 0 ? 'first' : ''} ${sel ? 'sel' : ''}">
                        <td>${i === 0 ? `<b>${esc(type === 'GA' ? 'Go-around' : p.id)}</b>` : ''}</td>
                        <td><span class="rwy">${esc(ident)}</span></td>
                        <td class="route">${fixes.map(esc).join(' <span class="arrow">›</span> ')}</td>
                        <td class="r"><button class="osa-btn small" data-proc="${esc(p.id)}" data-ident="${esc(ident)}">Map</button></td></tr>`;
                });
            }
            html += '</tbody></table></section>';
        }
        $('procBody').innerHTML = html;
    }

    $('procBody').addEventListener('click', e => {
        const b = e.target.closest('button[data-proc]');
        if (!b) return;
        const p = nav.procedures.find(x => x.id === b.dataset.proc);
        if (!p) return;
        shownProc = { id: p.id, ident: b.dataset.ident, airport: p.airport, type: p.type,
            fixes: arr(p.runways[b.dataset.ident]) };
        go('map');
    });

    // ------------------------------------------------------------------ map
    const COL = { cta: '#7c8aa5', tma: '#3d8bfd', ctr: '#e5484d', fix: '#d7dde8', navaid: '#2fbf6b', final: '#ffb52e', proc: '#ffb52e' };

    function polyPath(ctx, m, poly) {
        ctx.beginPath();
        arr(poly).forEach((p, i) => {
            const [sx, sy] = m.toScreen(p[0], p[1]);
            if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
        });
    }

    function drawMap(ctx, m) {
        if (!nav) return;
        const font = Math.round(Math.max(10, Math.min(13, 9 + m.zoom * 6)));
        ctx.font = `600 ${font}px Consolas, monospace`;
        ctx.textBaseline = 'middle';
        // airspaces: CTA, then TMA, then CTR on top
        for (const kind of ['CTA', 'TMA', 'CTR']) {
            const key = kind.toLowerCase();
            if (!layers[key]) continue;
            for (const a of nav.airspaces.filter(s => s.type === kind)) {
                polyPath(ctx, m, a.polygon);
                ctx.closePath();
                if (kind !== 'CTA') { ctx.fillStyle = COL[key] + (kind === 'TMA' ? '14' : '22'); ctx.fill(); }
                ctx.setLineDash(kind === 'CTR' ? [6, 4] : []);
                ctx.strokeStyle = COL[key];
                ctx.lineWidth = kind === 'CTA' ? 2 : 1.6;
                ctx.stroke();
                ctx.setLineDash([]);
            }
        }
        if (layers.cta && nav.centre.line) {
            polyPath(ctx, m, nav.centre.line);
            ctx.setLineDash([10, 6]);
            ctx.strokeStyle = COL.cta;
            ctx.lineWidth = 1.4;
            ctx.stroke();
            ctx.setLineDash([]);
        }
        // runways
        for (const a of nav.airports) {
            for (const rw of arr(a.runways)) {
                const e = arr(rw.ends);
                if (e.length < 2) continue;
                const [x1, y1] = m.toScreen(e[0].x, e[0].y), [x2, y2] = m.toScreen(e[1].x, e[1].y);
                ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
                ctx.strokeStyle = '#ffffff'; ctx.lineWidth = Math.max(2, m.zoom * 6); ctx.stroke();
            }
            const [ax, ay] = m.toScreen(a.arp[0], a.arp[1]);
            ctx.fillStyle = '#ffffff';
            ctx.fillText(a.icao, ax + 12, ay - 14);
        }
        // the procedure picked on the Procedures page
        if (shownProc) {
            const pts = shownProc.fixes.map(point).filter(Boolean);
            const rwy = nav.airports.find(a => a.icao === shownProc.airport);
            const end = rwy && arr(rwy.runways).flatMap(r => arr(r.ends)).find(e => e.ident === shownProc.ident);
            if (shownProc.type === 'SID' && end) pts.unshift(end);
            if (shownProc.type !== 'SID' && end && pts.length && pts[pts.length - 1].kind === 'final') pts.push(end);
            ctx.beginPath();
            pts.forEach((p, i) => { const [sx, sy] = m.toScreen(p.x, p.y); if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy); });
            ctx.strokeStyle = 'rgba(0,0,0,.6)'; ctx.lineWidth = 6; ctx.stroke();
            ctx.strokeStyle = COL.proc; ctx.lineWidth = 3; ctx.stroke();
        }
        // nav points
        const procFix = new Set(shownProc ? shownProc.fixes : []);
        for (const p of nav.points) {
            const isNavaid = p.type === 'VOR' || p.type === 'NDB';
            const isFinal = p.kind === 'final';
            const show = procFix.has(p.id) ||
                (isNavaid ? layers.navaid : isFinal ? layers.final : (p.kind !== 'proc' && layers.fix));
            if (!show) continue;
            const [sx, sy] = m.toScreen(p.x, p.y);
            ctx.fillStyle = procFix.has(p.id) ? COL.proc : isNavaid ? COL.navaid : isFinal ? COL.final : COL.fix;
            ctx.beginPath();
            if (isNavaid) { ctx.arc(sx, sy, 4, 0, Math.PI * 2); }
            else { ctx.moveTo(sx, sy - 5); ctx.lineTo(sx + 4.5, sy + 3.5); ctx.lineTo(sx - 4.5, sy + 3.5); ctx.closePath(); }
            ctx.fill();
            ctx.fillText(p.id, sx + 7, sy);
        }
    }

    function showMap() {
        if (!nav) return;
        if (!map) {
            map = new OSA.Map($('map'), { maxZoom: 4 });
            map.addLayer(drawMap);
        }
        $('mapProc').innerHTML = shownProc
            ? `<b>${esc(shownProc.type === 'GA' ? 'Go-around' : shownProc.id)}</b> runway ${esc(shownProc.ident)}<br>
               <span class="route">${shownProc.fixes.map(esc).join(' › ')}</span><br>
               <button class="osa-btn small" id="clearProc">Clear</button>`
            : 'None. Pick one on the Procedures page.';
        // the map was hidden until now: size it on the next frame, then fit the CTA (or the procedure)
        requestAnimationFrame(() => {
            map._resized && map._resized();
            const pts = shownProc ? shownProc.fixes.map(point).filter(Boolean) : [];
            if (pts.length) {
                const xs = pts.map(p => p.x), ys = pts.map(p => p.y);
                map.fitBox(Math.min(...xs) - 600, Math.min(...ys) - 600, Math.max(...xs) + 600, Math.max(...ys) + 600, 40);
            } else if (!mapFitted) {
                map.fitBox(-6000, -6000, 6000, 6000, 20);
            }
            mapFitted = true;
            map.redraw();
        });
    }

    $('mapProc').addEventListener('click', e => {
        if (e.target.id !== 'clearProc') return;
        shownProc = null;
        showMap();
    });
    document.querySelectorAll('[data-layer]').forEach(cb => cb.addEventListener('change', () => {
        layers[cb.dataset.layer] = cb.checked;
        if (map) map.redraw();
    }));

    // ------------------------------------------------------------------ data
    async function loadStatus() {
        status = await api.call('sacGetStatus');
        if (status && status.time) OSA.time.sync(status.time);
        renderStatus();
    }

    async function init() {
        try { docs = arr(await api.call('sacGetDocuments')); } catch (e) { docs = []; }
        renderHomeDocs();
        renderDocList();
        try {
            const n = await api.call('sacGetNav');
            nav = {
                airports: arr(n.airports), airspaces: arr(n.airspaces), centre: n.centre || {},
                points: arr(n.points), procedures: arr(n.procedures), byId: {},
            };
            nav.airports.forEach(a => { a.runways = arr(a.runways); });
            nav.points.forEach(p => { nav.byId[p.id] = p; });
        } catch (e) {
            nav = { airports: [], airspaces: [], centre: {}, points: [], procedures: [], byId: {} };
        }
        OSA.poll(loadStatus, STATUS_MS, { onFail: n => { if (n === 1) OSA.toast('No connection to the server', false); } });
        tickClock();
        go((location.hash || '').replace(/^#\/?/, '') || 'home');
    }
    init();
})();
