// The dispatch map: task dots and unit labels on the shared OSA.Map (v_radar bigmap).
(function () {
    'use strict';

    // marker keys: 't<taskId>' task dot, 'u<unitId>' unit label
    const map = new OSA.Map(document.getElementById('map'), {
        onMarkerCreate(m, key) {
            const kind = key[0], id = Number(key.slice(1));
            const app = ERM.app;
            m._kind = kind;
            m._id = id;

            m.addEventListener('mouseenter', e => ERM.ui.showTip(m, kind === 't' ? app.taskTip(id) : app.unitTip(id), e));
            m.addEventListener('mousemove', e => ERM.ui.moveTip(e));
            m.addEventListener('mouseleave', () => ERM.ui.hideTip(m));
            m.addEventListener('contextmenu', e => {
                e.preventDefault();
                if (kind === 't') app.taskMenu(e, id); else app.unitMenu(e, id);
            });

            if (kind === 't') m.addEventListener('click', () => app.selectTask(id));
            else app.makeDropTarget(m, id);
        },
    });

    // Unit labels that would cover each other are stacked upwards: the lowest
    // one on screen keeps its spot, the others are pushed above it. Labels
    // moved off their anchor drop the little position dot (.stacked).
    const LABEL_GAP = 2, LABEL_LIFT = 6;   // LIFT = .unit-label margin-top
    function stackLabels() {
        const labels = [];
        map.markers.forEach(m => { if (m._kind === 'u') labels.push(m); });
        labels.sort((a, b) => (b._sy - a._sy) || (a._sx - b._sx) || (a._id - b._id));

        const placed = [];   // { l, r, t, b }
        for (const m of labels) {
            if (!m._w) { m._w = m.offsetWidth; m._h = m.offsetHeight; }
            const l = m._sx - m._w / 2, r = m._sx + m._w / 2;
            let b = m._sy - LABEL_LIFT;
            for (let moved = true; moved;) {
                moved = false;
                for (const p of placed) {
                    if (l < p.r && r > p.l && b > p.t - LABEL_GAP && b - m._h < p.b + LABEL_GAP) {
                        b = p.t - LABEL_GAP;
                        moved = true;
                    }
                }
            }
            placed.push({ l, r, t: b - m._h, b });
            const dy = m._sy - LABEL_LIFT - b;
            if (dy !== (m._dy || 0)) {
                m._dy = dy;
                m.style.top = (m._sy - dy) + 'px';
            }
            m.classList.toggle('stacked', dy > 0);
        }
    }

    map.on('mapmove', stackLabels);
    map.on('mapclick', e => ERM.app.mapClick(e.detail.wx, e.detail.wy));
    map.on('mapcontext', e => ERM.app.mapMenu(e.detail.event, e.detail.wx, e.detail.wy));

    function update(tasks, units, selectedId) {
        const seen = new Set();

        for (const t of tasks) {
            const key = 't' + t.id;
            seen.add(key);
            const m = map.marker(key, t.x, t.y, 'task-dot ' + t.status + (t.id === selectedId ? ' selected' : ''));
            ERM.ui.updateTip(m, ERM.app.taskTip(t.id));
        }

        for (const u of units) {
            const key = 'u' + u.id;
            seen.add(key);
            const m = map.marker(key, u.x, u.y, 'unit-label bg-' + u.status + ' ' + u.status, ERM.esc(u.callsign));
            if (m._callsign !== u.callsign) { m._callsign = u.callsign; m._w = 0; }
            ERM.ui.updateTip(m, ERM.app.unitTip(u.id));
        }

        for (const [key, m] of [...map.markers]) {
            if (!seen.has(key)) {
                ERM.ui.hideTip(m);
                map.removeMarker(key);
            }
        }
        stackLabels();
    }

    ERM.map = { update, focus: (x, y, z) => map.focus(x, y, z), fit: () => map.fit() };
})();
