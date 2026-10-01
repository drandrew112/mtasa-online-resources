// Pan / zoom map with task dots and unit labels.
// The map image (v_radar bigmap) is 3072 px and covers world -3000..3000.
(function () {
    'use strict';

    const MAP_PX = 3072;
    const WORLD = 6000;

    const el = document.getElementById('map');
    const img = document.getElementById('mapImg');
    const layer = document.getElementById('markers');

    let zoom = 0.2, ox = 0, oy = 0, minZoom = 0.1, fitted = false;
    const MAX_ZOOM = 3;
    const markers = new Map();   // key -> element

    const toMap = (x, y) => [(x + WORLD / 2) / WORLD * MAP_PX, (WORLD / 2 - y) / WORLD * MAP_PX];

    function toWorld(sx, sy) {
        const mx = (sx - ox) / zoom, my = (sy - oy) / zoom;
        return [mx / MAP_PX * WORLD - WORLD / 2, WORLD / 2 - my / MAP_PX * WORLD];
    }

    function place(m) {
        const [mx, my] = toMap(m._x, m._y);
        m.style.left = (ox + mx * zoom) + 'px';
        m.style.top = (oy + my * zoom) + 'px';
    }

    function apply() {
        img.style.transform = `translate(${ox}px, ${oy}px) scale(${zoom})`;
        markers.forEach(place);
    }

    function fit() {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) return;
        fitted = true;
        zoom = Math.min(r.width, r.height) / MAP_PX;
        minZoom = zoom * 0.8;
        ox = (r.width - MAP_PX * zoom) / 2;
        oy = (r.height - MAP_PX * zoom) / 2;
        apply();
    }

    function zoomAt(factor, cx, cy) {
        const nz = Math.max(minZoom, Math.min(MAX_ZOOM, zoom * factor));
        ox = cx - (cx - ox) * nz / zoom;
        oy = cy - (cy - oy) * nz / zoom;
        zoom = nz;
        apply();
    }

    function focus(x, y, minZ) {
        const r = el.getBoundingClientRect();
        zoom = Math.max(zoom, minZ || 0.6);
        const [mx, my] = toMap(x, y);
        ox = r.width / 2 - mx * zoom;
        oy = r.height / 2 - my * zoom;
        apply();
    }

    /* ------------------------------------------------------------ input */

    el.addEventListener('wheel', e => {
        e.preventDefault();
        const r = el.getBoundingClientRect();
        zoomAt(e.deltaY < 0 ? 1.2 : 1 / 1.2, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });

    let pan = null;
    el.addEventListener('mousedown', e => {
        if (e.button !== 0 || e.target.closest('.task-dot, .unit-label')) return;
        pan = { x: e.clientX, y: e.clientY, ox, oy };
        el.classList.add('panning');
    });
    window.addEventListener('mousemove', e => {
        if (!pan) return;
        ox = pan.ox + e.clientX - pan.x;
        oy = pan.oy + e.clientY - pan.y;
        apply();
    });
    window.addEventListener('mouseup', e => {
        if (!pan) return;
        const moved = Math.abs(e.clientX - pan.x) + Math.abs(e.clientY - pan.y);
        pan = null;
        el.classList.remove('panning');
        if (moved < 5) {
            const r = el.getBoundingClientRect();
            const [wx, wy] = toWorld(e.clientX - r.left, e.clientY - r.top);
            ERM.app.mapClick(wx, wy);
        }
    });

    el.addEventListener('contextmenu', e => {
        e.preventDefault();
        if (e.target.closest('.task-dot, .unit-label')) return;
        const r = el.getBoundingClientRect();
        const [wx, wy] = toWorld(e.clientX - r.left, e.clientY - r.top);
        ERM.app.mapMenu(e, wx, wy);
    });

    document.getElementById('zoomIn').onclick = () => { const r = el.getBoundingClientRect(); zoomAt(1.4, r.width / 2, r.height / 2); };
    document.getElementById('zoomOut').onclick = () => { const r = el.getBoundingClientRect(); zoomAt(1 / 1.4, r.width / 2, r.height / 2); };
    document.getElementById('zoomFit').onclick = fit;

    new ResizeObserver(() => { if (!fitted) fit(); else apply(); }).observe(el);

    /* ------------------------------------------------------------ markers */

    function makeMarker(key, kind, id) {
        const m = document.createElement('div');
        m._kind = kind;
        m._id = id;
        const app = ERM.app;

        m.addEventListener('mouseenter', e => ERM.ui.showTip(m, kind === 't' ? app.taskTip(id) : app.unitTip(id), e));
        m.addEventListener('mousemove', e => ERM.ui.moveTip(e));
        m.addEventListener('mouseleave', () => ERM.ui.hideTip(m));
        m.addEventListener('contextmenu', e => {
            e.preventDefault();
            kind === 't' ? app.taskMenu(e, id) : app.unitMenu(e, id);
        });

        if (kind === 't') {
            m.addEventListener('click', () => app.selectTask(id));
        } else {
            app.makeDropTarget(m, id);
        }
        layer.appendChild(m);
        markers.set(key, m);
        return m;
    }

    function update(tasks, units, selectedId) {
        const seen = new Set();

        for (const t of tasks) {
            const key = 't' + t.id;
            seen.add(key);
            const m = markers.get(key) || makeMarker(key, 't', t.id);
            m.className = 'task-dot ' + t.status + (t.id === selectedId ? ' selected' : '');
            m._x = t.x; m._y = t.y;
            place(m);
            ERM.ui.updateTip(m, ERM.app.taskTip(t.id));
        }

        for (const u of units) {
            const key = 'u' + u.id;
            seen.add(key);
            const m = markers.get(key) || makeMarker(key, 'u', u.id);
            const drop = m.classList.contains('drop-ok') ? ' drop-ok' : '';
            m.className = 'unit-label bg-' + u.status + ' ' + u.status + drop;
            m.textContent = u.callsign;
            m._x = u.x; m._y = u.y;
            place(m);
            ERM.ui.updateTip(m, ERM.app.unitTip(u.id));
        }

        markers.forEach((m, key) => {
            if (!seen.has(key)) {
                ERM.ui.hideTip(m);
                m.remove();
                markers.delete(key);
            }
        });
    }

    img.addEventListener('load', fit);
    // In game the page is a local CEF page: use v_radar's copy of the map that
    // every client already has instead of shipping a second 6 MB file.
    img.src = ERM.inGame ? 'http://mta/v_radar/radar/files/radar.png' : 'img/map.png';

    ERM.map = { update, focus, fit };
})();
