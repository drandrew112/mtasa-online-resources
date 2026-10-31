// police_web - the public police site: Join the police (ranks), Statistics, Warrants (public, no positions),
// Penal code. One call: policeWebStats (police_system getPublicStats, cached 60 s there). No map.
(function () {
    'use strict';
    const api = OSA.api();
    const esc = OSA.esc, arr = OSA.arr;
    const $ = id => document.getElementById(id);
    const money = n => '€' + Math.round(Number(n) || 0).toLocaleString('en-US');
    let data = null;

    // tabs (the page scrolls; the top bar stays)
    function show(tab) {
        for (const a of document.querySelectorAll('[data-tab]')) a.classList.toggle('on', a.dataset.tab === tab && a.closest('#nav'));
        for (const s of document.querySelectorAll('.pw-tab')) s.classList.toggle('hidden', s.id !== 'tab-' + tab);
        window.scrollTo(0, 0);
        if (location.hash !== '#' + tab) history.replaceState(null, '', '#' + tab);
    }
    document.addEventListener('click', e => {
        const a = e.target.closest('[data-tab]');
        if (a) { e.preventDefault(); show(a.dataset.tab); }
    });

    const kpi = (k, v) => `<div class="pw-kpi"><div class="v">${esc(String(v))}</div><div class="k">${esc(k)}</div></div>`;

    function render() {
        if (!data) return;
        const d = data;
        const w = d.week || {}, t = d.today || {}, m = d.month || {};
        $('liveKpis').innerHTML = kpi('Officers on duty', d.officers || 0) + kpi('Units on duty', d.units || 0) +
            kpi('Active pursuits', d.pursuits || 0) + kpi('Wanted now', d.wanted || 0);
        $('statKpis').innerHTML = kpi('Arrests today', t.arrests || 0) + kpi('Arrests this week', w.arrests || 0) +
            kpi('Fines this week', w.fines || 0) + kpi('Evasion rate (week)', (d.evadeRate || 0) + '%') +
            kpi('Pursuits this week', w.pursuits || 0) + kpi('Fine income (30 days)', money(m.fine_amount || 0)) +
            kpi('Warrants issued (30 days)', m.warrants || 0) + kpi('Calls (30 days)', m.calls || 0);
        const ranks = arr(d.ranks);
        $('ranks').innerHTML = ranks.map((name, i) => `<div class="pw-rank"><img src="${POLICE_RANK_IMAGES[i] || ''}" alt="">` +
            `<b>${esc(name)}</b><small>Rank ${i + 1}</small></div>`).join('');
        // chart: arrests, fines, pursuits, evaded per day
        const daily = arr(d.daily);
        const max = Math.max(1, ...daily.map(x => Math.max(x.arrests, x.fines, x.pursuits, x.evaded)));
        $('chart').innerHTML = daily.map(x => `<div class="pw-day" title="${esc(x.day)}">` +
            ['arrests', 'fines', 'pursuits', 'evaded'].map(k => `<span class="b-${k}" style="height:${Math.round(x[k] / max * 100)}%"></span>`).join('') +
            `<i>${esc(String(x.day).slice(5))}</i></div>`).join('');
        $('daily').innerHTML = '<tr><th>Day</th><th class="r">Arrests</th><th class="r">Fines</th><th class="r">Fine income</th><th class="r">Pursuits</th><th class="r">Evaded</th></tr>' +
            daily.slice().reverse().map(x => `<tr><td>${esc(x.day)}</td><td class="r">${x.arrests}</td><td class="r">${x.fines}</td>` +
                `<td class="r">${money(x.fine_amount)}</td><td class="r">${x.pursuits}</td><td class="r">${x.evaded}</td></tr>`).join('');
        const ws = arr(d.warrants);
        $('warrants').innerHTML = ws.length ? ws.map(x => `<div class="pw-warrant"><b>${esc(OSA.clean(x.name || '?'))}</b>` +
            `<div class="r">${arr(x.reasons).map(esc).join(', ')}</div>` +
            (x.description ? `<div class="d">"${esc(x.description)}" <small>(${esc(String(x.lang || '').toUpperCase())})</small></div>` : '') +
            `<small>Warrant #${x.id} · issued ${new Date((x.at || 0) * 1000).toISOString().slice(0, 10)}</small></div>`).join('')
            : '<div class="pw-empty">There are no active warrants.</div>';
        $('penal').innerHTML = arr(d.penal).map(c => `<div class="pw-cat">${esc(c.name)}</div><table class="pw-table">` +
            arr(c.items).map(i => `<tr><td>${esc(i.name)}</td><td class="r">${c.warning ? 'warning' : money(i.amount)}</td></tr>`).join('') +
            '</table>').join('');
        $('updated').textContent = 'Updated ' + new Date((d.updated || 0) * 1000).toLocaleTimeString();
    }

    async function load() {
        try {
            const r = await api.call('policeWebStats');
            if (r && r.ok) { data = r.data; render(); }
        } catch (e) { /* the next poll tries again */ }
    }

    show((location.hash || '#home').slice(1) || 'home');
    OSA.poll(load, 30000);
})();
