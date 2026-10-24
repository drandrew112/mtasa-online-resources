// gov_web - Open government of San Andreas. One read-only call (govWebState = v_gov's public
// snapshot, money data of the last 30 days) every minute; the same page over HTTP and in game.
(function () {
    'use strict';
    const api = OSA.api();
    const esc = OSA.esc;
    const arr = OSA.arr;
    const $ = id => document.getElementById(id);

    const GROUP = {
        tax: 'Taxes', fine: 'Fines', health: 'Healthcare', work: 'Wages', biz: 'Organizations', gov: 'State transfers',
        atc: 'Aviation', transfer: 'Transfers', admin: 'Administration', shop: 'Shopping', cash: 'Cash', other: 'Other',
    };
    const VAT = {
        weapons: 'Weapons and ammunition', clothing: 'Clothing', vehicles: 'Vehicles', tuning: 'Vehicle tuning',
        repair: 'Vehicle repair', services: 'Services (insurance, phone services)', real_estate: 'Real estate (organization properties)',
    };
    const FEE = {
        register: 'Company registration fee', rename: 'Company rename fee', bay_fine: 'Ambulance bay fine (per interval)',
        'airspace.takeoff': 'Airspace fee: takeoff', 'airspace.landing': 'Airspace fee: landing', 'airspace.overflight': 'Airspace fee: overflight',
    };

    const money = n => (n < 0 ? '−€' : '€') + Math.abs(Math.round(Number(n) || 0)).toLocaleString('en-US');
    const signed = n => (n > 0 ? '+' : '') + money(n);
    const cls = n => (n < 0 ? 'neg' : 'pos');
    const pct = (r, d) => (Math.round((Number(r) || 0) * Math.pow(10, 2 + (d || 1))) / Math.pow(10, d || 1)) + '%';
    const date = ts => new Date(ts * 1000).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' });
    const dateTime = ts => new Date(ts * 1000).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
    const table = (cols, rows) => rows.length ? `<table class="gw-table"><thead><tr>${cols.map(c =>
        `<th class="${c[1] || ''}">${esc(c[0])}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table>` : '<div class="gw-empty">Nothing here yet.</div>';
    const kpi = (k, v, c, s) => `<div class="gw-kpi"><div class="k">${esc(k)}</div><div class="v ${c || ''}">${v}</div>${s ? `<div class="s">${esc(s)}</div>` : ''}</div>`;
    const groups = list => table([['Category'], ['Income', 'r'], ['Expense', 'r'], ['Net', 'r']], arr(list).map(g =>
        `<tr><td>${esc(GROUP[g.group] || g.group)}</td><td class="r mono pos">+${money(g.inSum)}</td><td class="r mono neg">-${money(g.outSum)}</td>` +
        `<td class="r mono ${cls(g.inSum - g.outSum)}">${signed(g.inSum - g.outSum)}</td></tr>`));

    function render(s) {
        const days = s.days || 30;
        const t = s.treasury || {};
        const companies = arr(s.companies);
        const tx = s.taxes || {};
        $('updated').textContent = 'Updated ' + dateTime(s.updated || s.now);
        $('foot').textContent = `Money data of the last ${days} days only. Updated every minute.`;
        $('lead').textContent = `The ${t.name || 'State Treasury'} and ${companies.length} state ${companies.length === 1 ? 'company' : 'companies'}, the last ${days} days.`;

        const stateTotal = companies.reduce((a, c) => a + (Number(c.balance) || 0), 0);
        $('kpis').innerHTML = kpi('Treasury balance', money(t.balance), cls(t.balance)) +
            kpi(`Treasury income (${days} d)`, money(t.inSum), 'pos') +
            kpi(`Treasury expense (${days} d)`, money(t.outSum), 'neg') +
            kpi('State companies', money(stateTotal), cls(stateTotal), `${companies.length} companies`) +
            kpi(`Company tax (${days} d)`, money(tx.runs && tx.runs.total), 'pos', `${(tx.runs && tx.runs.count) || 0} hourly runs`);

        const daily = arr(s.daily);
        const max = Math.max(1, ...daily.map(d => Math.max(d.inSum, d.outSum)));
        $('daily').innerHTML = daily.length ? `<div class="gw-bars">${daily.map(d =>
            `<div class="gw-bar" title="${esc(date(d.day))}: +${money(d.inSum)} / -${money(d.outSum)}"><i class="in" style="height:${Math.round(d.inSum / max * 100)}%"></i>` +
            `<i class="out" style="height:${Math.round(d.outSum / max * 100)}%"></i></div>`).join('')}</div>` +
            `<div class="gw-axis"><span>${esc(date(daily[0].day))}</span><span>${esc(date(daily[daily.length - 1].day))}</span></div>` : '<div class="gw-empty">No movement yet.</div>';
        $('treasuryGroups').innerHTML = groups(t.groups);

        $('companies').innerHTML = companies.length ? companies.map(c => `<div class="gw-card gw-co"><h2>${esc(c.name)}</h2>` +
            (c.description ? `<p>${esc(c.description)}</p>` : '') +
            `<div class="bal ${cls(c.balance)}">${money(c.balance)}</div>` +
            `<div class="gw-sum"><span class="pos">+${money(c.inSum)}</span><span class="neg">-${money(c.outSum)}</span><b class="${cls(c.inSum - c.outSum)}">${signed(c.inSum - c.outSum)}</b></div>` +
            (arr(c.works).length ? `<div style="margin-bottom:10px">${arr(c.works).map(w => `<span class="gw-tag">${esc(w)}</span>`).join('')}</div>` : '') +
            groups(c.groups) + '</div>').join('') : '<div class="gw-empty">There is no state company yet.</div>';

        $('corpTax').innerHTML = table([['Tax'], ['Rate', 'r']], [
            `<tr><td>Company income tax (hourly, on the net legal income)</td><td class="r mono">${pct(tx.company)}</td></tr>`,
            `<tr><td>Property tax (of the property price, every 24 online hours)</td><td class="r mono">${pct(tx.property, 2)}</td></tr>`,
        ]);
        $('incomeTax').innerHTML = table([['Key'], ['Rate', 'r']], Object.entries(tx.income || {}).sort((a, b) => a[0].localeCompare(b[0]))
            .map(([k, r]) => `<tr><td>${esc(k)}</td><td class="r mono">${pct(r)}</td></tr>`));
        $('vat').innerHTML = table([['Product group'], ['VAT', 'r']], arr(tx.vat).map(v =>
            `<tr><td>${esc(VAT[v.group] || v.group)}</td><td class="r mono">${pct(v.rate)}</td></tr>`));

        $('feeList').innerHTML = table([['Fee'], ['Amount', 'r']], arr(s.fees).map(f =>
            `<tr><td>${esc(FEE[f.key] || f.key)}</td><td class="r mono">${money(f.value)}</td></tr>`));
        const h = s.health || {};
        const inj = Object.entries(h.injuries || {}).sort((a, b) => a[0].localeCompare(b[0]));
        $('health').innerHTML = `<p class="gw-muted" style="margin-top:0">${h.enabled ? 'Treatment is free for the patient; the State Treasury pays the hospital.' : 'State healthcare is switched off.'}</p>` +
            table([['Item'], ['Severity 1', 'r'], ['Severity 2', 'r'], ['Severity 3', 'r']], [
                `<tr><td>1 HP restored</td><td class="r mono" colspan="3">${money(h.hpPrice)}</td></tr>`,
                ...inj.map(([k, p]) => `<tr><td>${esc(k.replace(/_/g, ' '))}</td>${[0, 1, 2].map(i => `<td class="r mono">${money(arr(p)[i])}</td>`).join('')}</tr>`),
            ]);

        $('workList').innerHTML = table([['Work'], ['Paid by'], ['Multiplier', 'r'], ['Income tax', 'r']], arr(s.works).map(w =>
            `<tr><td>${esc(w.name)}</td><td>${esc(w.payer)}</td><td class="r mono">×${esc(w.multiplier)}</td><td class="r mono">${esc(w.taxKey)} (${pct(w.taxRate)})</td></tr>`));

        const votes = arr(s.votes);
        $('voteList').innerHTML = votes.length ? votes.map(v => {
            const opts = arr(v.options), res = arr(v.results);
            const total = res.reduce((a, n) => a + n, 0), best = Math.max(0, ...res);
            const closed = v.status === 'closed';
            const body = closed ? opts.map((o, i) => {
                const n = res[i] || 0, p = total ? Math.round(n / total * 1000) / 10 : 0;
                return `<div class="gw-res${n === best && n > 0 ? ' win' : ''}"><div class="row"><span>${esc(o)}</span><span class="mono">${n} · ${p}%</span></div>` +
                    `<div class="gw-meter"><i style="width:${p}%"></i></div></div>`;
            }).join('') : `<div>${opts.map(o => `<span class="gw-tag">${esc(o)}</span>`).join('')}</div>`;
            return `<div class="gw-card gw-vote"><h3>${esc(v.title)}<span class="gw-status${closed ? ' closed' : ''}">${closed ? 'Closed' : 'Open'}</span></h3>` +
                `<div class="meta">${v.voters} voters · ${closed ? 'closed' : 'closes'} ${esc(dateTime(closed ? (v.closedAt || v.endsAt) : v.endsAt))}</div>` +
                (v.description ? `<p class="desc">${esc(v.description)}</p>` : '') + body + '</div>';
        }).join('') : '<div class="gw-empty">No vote in the last 30 days.</div>';
    }

    const offline = () => { $('lead').textContent = 'The government data is not available right now.'; };
    OSA.poll(async () => {
        const s = await api.call('govWebState');
        if (!s || !s.ok) return offline();
        render(s);
    }, 60000, { onFail: offline });
})();
