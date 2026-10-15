// Blood Transport web page: navigation, the public state poll and shared helpers.
// Works over HTTP and inside ui_browser (web_api bridge); the page code is the same.
(function () {
    'use strict';

    const api = OSA.api();
    const $ = id => document.getElementById(id);

    const BT = window.BT = {
        api, $,
        esc: OSA.esc, arr: OSA.arr, clean: OSA.clean,
        state: null,                 // last btPublic result
        listeners: [],
        on(fn) { BT.listeners.push(fn); if (BT.state) fn(BT.state); },
        view: 'home',
    };

    BT.PRODUCT = { rbc: 'RBC', ffp: 'FFP', platelets: 'Platelets' };
    BT.TYPE = {
        resupply: 'Hospital resupply', urgent_blood: 'Urgent blood', planned_blood: 'Planned surgery blood',
        lab_sample: 'Lab sample', urgent_medicine: 'Urgent medicine',
    };
    BT.STATUS = { waiting: 'Waiting', transit: 'In transit', delivered: 'Delivered', cancelled: 'Cancelled' };
    BT.STATUS_COLOR = { waiting: '#3884f4', transit: '#e6be28', delivered: '#2ea043', cancelled: '#6e7682' };

    // "RBC 0+ x4", "Lab sample x1"
    BT.what = t => {
        let s;
        if (t.type === 'lab_sample') s = 'Lab sample';
        else if (t.type === 'urgent_medicine') s = 'Urgent medicine';
        else s = (BT.PRODUCT[t.product] || t.product) + (t.group ? ' ' + t.group : '');
        return s + ' ×' + (t.units || 1);
    };

    BT.duration = sec => {
        sec = Math.max(0, Math.floor(sec || 0));
        const p = n => String(n).padStart(2, '0');
        return sec >= 3600 ? `${Math.floor(sec / 3600)}:${p(Math.floor(sec % 3600 / 60))}:${p(sec % 60)}` : `${p(Math.floor(sec / 60))}:${p(sec % 60)}`;
    };

    BT.instName = id => {
        const i = BT.state && BT.arr(BT.state.institutions).find(x => x.id === id);
        return i ? i.name : id;
    };

    /* ---------------------------------------------------------------- navigation */
    const views = ['home', 'map', 'admin'];
    function show(view) {
        if (!views.includes(view)) view = 'home';
        BT.view = view;
        for (const v of views) {
            $('v' + v[0].toUpperCase() + v.slice(1)).hidden = v !== view;
        }
        document.querySelectorAll('#nav .osa-tab').forEach(b => b.classList.toggle('active', b.dataset.view === view));
        BT.listeners.forEach(fn => fn(BT.state, view));
        if (view === 'map' && BT.mapResize) BT.mapResize();
    }
    BT.show = show;
    document.querySelectorAll('#nav .osa-tab').forEach(b => b.addEventListener('click', () => { location.hash = b.dataset.view; show(b.dataset.view); }));
    document.querySelectorAll('[data-go]').forEach(a => a.addEventListener('click', e => { e.preventDefault(); location.hash = a.dataset.go; show(a.dataset.go); }));
    window.addEventListener('hashchange', () => { const h = location.hash.slice(1); if (views.includes(h)) show(h); });

    /* ---------------------------------------------------------------- clock + poll */
    setInterval(() => {
        const d = new Date(), p = n => String(n).padStart(2, '0');
        $('clock').textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    }, 1000);

    OSA.poll(async () => {
        const r = await api.call('btPublic');
        if (!r || r.ok === false) throw new Error('bad response');
        BT.state = r;
        BT.listeners.forEach(fn => fn(r, BT.view));
    }, 3000, {
        onOk: () => { $('conn').className = 'osa-conn ok'; },
        onFail: () => { $('conn').className = 'osa-conn bad'; },
    });

    const first = location.hash.slice(1);
    show(views.includes(first) ? first : 'home');
})();
