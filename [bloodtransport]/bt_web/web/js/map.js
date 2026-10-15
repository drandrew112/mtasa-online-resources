// Map: units, institutions (hover info), the unit list and the public stock.
(function () {
    'use strict';
    const { $, esc, arr, clean } = BT;

    const map = new OSA.Map($('map'), {
        onMarkerCreate(m, key) {
            m.addEventListener('mouseenter', e => OSA.ui.showTip(m, m._tip || '', e));
            m.addEventListener('mousemove', e => OSA.ui.moveTip(e));
            m.addEventListener('mouseleave', () => OSA.ui.hideTip(m));
        },
    });
    BT.mapResize = () => { if (!map.fitted) map.fit(); };

    let stock = null, stockKind = 'bank';

    /* ---------------------------------------------------------------- tooltips */
    function unitTip(u) {
        const tasks = arr(u.tasks);
        return `<div class="tip-title">${esc(u.unit)} <span class="tip-dim">driver: ${esc(clean(u.driver))}</span></div>`
            + `<div class="tip-dim">${tasks.length ? 'Current tasks' : 'No tasks right now'}${u.windDown ? ' &middot; winding down' : ''}</div>`
            + tasks.map(t => `<div class="tip-line">T-${t.id} ${esc(BT.what(t))} &rarr; ${esc(BT.instName(t.to))} <span class="tip-dim">&middot; ${esc(BT.STATUS[t.status] || t.status)}</span></div>`).join('');
    }

    function lowLines(inst) {
        if (!stock || !stock[inst.id]) return [];
        const out = [];
        const lines = stock[inst.id].lines;
        for (const p of Object.keys(lines)) {
            for (const g of Object.keys(lines[p])) {
                const l = lines[p][g];
                if (l.cap && l.have / l.cap < 0.25) out.push((BT.PRODUCT[p] || p) + ' ' + g);
            }
        }
        return out;
    }

    function instTip(inst, openTasks) {
        const low = lowLines(inst);
        const kind = inst.kind === 'bank' ? 'Blood supply center' : 'Hospital';
        return `<div class="tip-title">${esc(inst.name)}</div><div class="tip-dim">${kind}</div>`
            + `<div class="tip-line">Stock: ${stock ? (low.length ? 'low: ' + esc(low.slice(0, 4).join(', ')) + (low.length > 4 ? ' +' + (low.length - 4) : '') : 'OK') : '...'}</div>`
            + `<div class="tip-line">Open tasks: ${openTasks}</div>`;
    }

    /* ---------------------------------------------------------------- map + list */
    function render(s) {
        if (!s) return;
        const units = arr(s.units);
        const keep = new Set();

        for (const inst of arr(s.institutions)) {
            const key = 'i:' + inst.id;
            keep.add(key);
            const open = units.reduce((n, u) => n + arr(u.tasks).filter(t => t.from === inst.id || t.to === inst.id).length, 0);
            const m = map.marker(key, inst.x, inst.y, 'bt-inst ' + inst.kind);
            m._tip = instTip(inst, open);
            OSA.ui.updateTip(m, m._tip);
        }
        for (const u of units) {
            const key = 'u:' + u.unit;
            keep.add(key);
            const m = map.marker(key, u.x, u.y, 'bt-unit', esc(u.unit));
            m._tip = unitTip(u);
            OSA.ui.updateTip(m, m._tip);
        }
        map.removeMissing('i:', keep);
        map.removeMissing('u:', keep);

        $('countUnits').textContent = units.length;
        $('unitList').innerHTML = units.length ? units.map(u => `<li class="unit-row">
            <div class="top"><b>${esc(u.unit)}</b><span class="ok">${u.delivered} delivered</span></div>
            <div class="top"><span class="dim">${esc(clean(u.driver))}</span><span class="dim">on duty ${BT.duration(u.since)}</span></div></li>`).join('')
            : '<li class="osa-empty">Nobody is on duty.</li>';
    }

    /* ---------------------------------------------------------------- stock */
    function levelColor(r) { return r > 0.45 ? '#2ea043' : r > 0.25 ? '#e6be28' : '#da3633'; }

    function renderStock() {
        const s = BT.state;
        if (!stock || !s) { $('stockList').innerHTML = '<div class="osa-empty">Loading...</div>'; return; }
        const html = arr(s.institutions).filter(i => i.kind === stockKind).map(inst => {
            const st = stock[inst.id];
            if (!st) return '';
            const prods = Object.keys(st.lines).map(p => {
                const groups = Object.keys(st.lines[p]);
                return `<div class="prod"><b>${esc(BT.PRODUCT[p] || p)}</b>` + groups.map(g => {
                    const l = st.lines[p][g], r = l.cap ? l.have / l.cap : 0;
                    return `<div class="cell" title="${l.have} / ${l.cap} units"><span>${esc(g)}</span><div class="bar"><i style="width:${Math.round(Math.min(1, r) * 100)}%;background:${levelColor(r)}"></i></div></div>`;
                }).join('') + '</div>';
            }).join('');
            return `<div class="inst"><h4>${esc(inst.name)}</h4>${prods}</div>`;
        }).join('');
        $('stockList').innerHTML = html;
    }

    document.querySelectorAll('#stockTabs .osa-tab').forEach(b => b.addEventListener('click', () => {
        stockKind = b.dataset.kind;
        document.querySelectorAll('#stockTabs .osa-tab').forEach(x => x.classList.toggle('active', x === b));
        renderStock();
    }));

    async function fetchStock() {
        const r = await BT.api.call('btStock');
        if (r && r.ok) { stock = r.stock; renderStock(); render(BT.state); }
    }
    OSA.poll(async () => { if (BT.view === 'map') await fetchStock(); }, 8000);

    let asked = false;
    BT.on((s, view) => {
        render(s);
        if (view === 'map' && !stock && !asked) { asked = true; fetchStock().finally(() => { asked = false; }); }
    });
})();
