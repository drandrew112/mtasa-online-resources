// Pan / zoom map: v_radar's bigmap image (3072 px = world -3000..3000), the tracks drawn on
// a canvas, and DOM markers for stations / trains / signals / switches.
(function () {
    'use strict';

    const MAP_PX = 3072, WORLD = 6000, MAX_ZOOM = 4;
    const el = document.getElementById('map');
    const img = document.getElementById('mapImg');
    const canvas = document.getElementById('mapCanvas');
    const ctx = canvas.getContext('2d');
    const layer = document.getElementById('markers');

    let zoom = 0.3, ox = 0, oy = 0, minZoom = 0.1;
    let tracks = [];
    const markers = new Map();

    const toMap = (x, y) => [(x + WORLD / 2) / WORLD * MAP_PX, (WORLD / 2 - y) / WORLD * MAP_PX];
    const toScreen = (x, y) => { const [mx, my] = toMap(x, y); return [ox + mx * zoom, oy + my * zoom]; };

    function resizeCanvas() {
        const r = el.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        canvas.width = Math.max(1, r.width * dpr);
        canvas.height = Math.max(1, r.height * dpr);
        canvas.style.width = r.width + 'px';
        canvas.style.height = r.height + 'px';
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function drawTracks() {
        const r = el.getBoundingClientRect();
        ctx.clearRect(0, 0, r.width, r.height);
        const w = Math.max(2, Math.min(6, zoom * 9));
        for (const t of tracks) {
            const pts = t.points;
            if (!pts.length) continue;
            ctx.beginPath();
            pts.forEach((p, i) => {
                const [sx, sy] = toScreen(p[0], p[1]);
                if (i === 0) ctx.moveTo(sx, sy); else ctx.lineTo(sx, sy);
            });
            if (t.closed) ctx.closePath();
            ctx.lineJoin = 'round';
            ctx.strokeStyle = 'rgba(0,0,0,.55)';
            ctx.lineWidth = w + 3;
            ctx.stroke();
            ctx.strokeStyle = t.id === 0 ? '#ffb52e' : (t.id === 3 ? '#59a8ff' : '#c58cff');
            ctx.lineWidth = w;
            ctx.stroke();
        }
    }

    function place(m) {
        const [sx, sy] = toScreen(m._x, m._y);
        m.style.left = sx + 'px';
        m.style.top = sy + 'px';
    }

    function apply() {
        img.style.transform = `translate(${ox}px, ${oy}px) scale(${zoom})`;
        drawTracks();
        markers.forEach(place);
        el.dispatchEvent(new CustomEvent('mapmove'));
    }

    function fitBox(minX, minY, maxX, maxY, pad) {
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) return false;
        pad = pad || 60;
        const [ax, ay] = toMap(minX, maxY), [bx, by] = toMap(maxX, minY);
        zoom = Math.min((r.width - pad * 2) / (bx - ax), (r.height - pad * 2) / (by - ay));
        zoom = Math.max(minZoom, Math.min(MAX_ZOOM, zoom));
        ox = r.width / 2 - (ax + bx) / 2 * zoom;
        oy = r.height / 2 - (ay + by) / 2 * zoom;
        apply();
        return true;
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
        zoom = Math.max(zoom, minZ || 0.8);
        const [mx, my] = toMap(x, y);
        ox = r.width / 2 - mx * zoom;
        oy = r.height / 2 - my * zoom;
        apply();
    }

    /* ---------------------------------------------------------------- input */
    el.addEventListener('wheel', e => {
        e.preventDefault();
        const r = el.getBoundingClientRect();
        zoomAt(e.deltaY < 0 ? 1.2 : 1 / 1.2, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });

    let pan = null;
    el.addEventListener('mousedown', e => {
        if (e.button !== 0 || e.target.closest('.m.station, .m.train')) return;
        pan = { x: e.clientX, y: e.clientY, ox, oy, moved: false };
        el.classList.add('panning');
    });
    window.addEventListener('mousemove', e => {
        if (!pan) return;
        ox = pan.ox + e.clientX - pan.x;
        oy = pan.oy + e.clientY - pan.y;
        if (Math.abs(e.clientX - pan.x) + Math.abs(e.clientY - pan.y) > 4) pan.moved = true;
        apply();
    });
    window.addEventListener('mouseup', () => {
        if (!pan) return;
        if (!pan.moved) el.dispatchEvent(new CustomEvent('mapclick'));
        pan = null;
        el.classList.remove('panning');
    });

    // touch: one finger pans
    let touch = null;
    el.addEventListener('touchstart', e => {
        if (e.touches.length !== 1 || e.target.closest('.m.station, .m.train')) return;
        touch = { x: e.touches[0].clientX, y: e.touches[0].clientY, ox, oy };
    }, { passive: true });
    el.addEventListener('touchmove', e => {
        if (!touch || e.touches.length !== 1) return;
        ox = touch.ox + e.touches[0].clientX - touch.x;
        oy = touch.oy + e.touches[0].clientY - touch.y;
        apply();
    }, { passive: true });
    el.addEventListener('touchend', () => { touch = null; });

    document.getElementById('zoomIn').onclick = () => { const r = el.getBoundingClientRect(); zoomAt(1.3, r.width / 2, r.height / 2); };
    document.getElementById('zoomOut').onclick = () => { const r = el.getBoundingClientRect(); zoomAt(1 / 1.3, r.width / 2, r.height / 2); };

    window.addEventListener('resize', () => { resizeCanvas(); apply(); });

    /* ---------------------------------------------------------------- api */
    window.RWMap = {
        init() {
            const r = el.getBoundingClientRect();
            minZoom = Math.min(r.width, r.height) / MAP_PX * 0.8;
            // HTTP: the page is the resource's default (/rw_core/), the image is web/img/map.png
            img.src = RWWEB.inGame ? 'http://mta/v_radar/radar/files/radar.png'
                : (location.pathname.includes('/web/') ? 'img/map.png' : 'web/img/map.png');
            resizeCanvas();
            apply();
        },
        setTracks(list) { tracks = list || []; apply(); },
        fitBox,
        focus,
        // key, kind -> element (created on first use). html only re-rendered when changed.
        marker(key, x, y, cls, html, onClick) {
            let m = markers.get(key);
            if (!m) {
                m = document.createElement('div');
                if (onClick) m.addEventListener('click', ev => { ev.stopPropagation(); onClick(ev); });
                layer.appendChild(m);
                markers.set(key, m);
            }
            if (m._cls !== cls) { m.className = cls; m._cls = cls; }
            if (html !== undefined && m._html !== html) { m.innerHTML = html; m._html = html; }
            m._x = x; m._y = y;
            place(m);
            return m;
        },
        removeMissing(prefix, keep) {
            markers.forEach((m, k) => {
                if (k.startsWith(prefix) && !keep.has(k)) { m.remove(); markers.delete(k); }
            });
        },
        el,
    };
})();
