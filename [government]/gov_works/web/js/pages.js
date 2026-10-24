// gov_works - the Works page of /gov (see gov_core web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, pct, numOf, head, empty, table, edit, select, payerName } = GOV.ui;
    const T = GOV.tr('gov_works');
    const sel = GOV.sel;
    sel.workQ = sel.workQ || '';

    GOV.page('works', {
        keys: GOV.keys('gov_works', ['multiplier', 'params', 'search_work']),
        render(d) {
            const m = GOV.can('minister');
            const q = sel.workQ.toLowerCase();
            const works = arr(d.works);
            const list = works.filter(w => !q || w.name.toLowerCase().includes(q) || w.id.includes(q));
            const w = works.find(x => x.id === sel.work) || works[0];
            if (w) sel.work = w.id;
            if (w && m) GOV.usePicker('pick', {
                state: () => arr(d.payers),
                current: () => w.payer,
                choose: it => GOV.change('setWork', { work: sel.work, field: 'payer', value: it.spec }),
            });
            let h = head(GOV.title('works')) + `<div class="gv-split"><div><input class="osa-input wide" id="workQ" placeholder="${esc(T('search_work'))}" value="${esc(sel.workQ)}" style="margin-bottom:8px">` +
                `<div class="gv-list">${list.map(x => {
                    const p = payerName(d, x.payer);
                    return `<a data-act="pickWork" data-id="${esc(x.id)}" class="${x === w ? 'on' : ''}"><span>${esc(x.name)}</span><small>${esc(p.name)}</small></a>`;
                }).join('') || empty()}</div></div>`;
            if (!w) return h + `<div>${empty()}</div></div>`;
            const p = payerName(d, w.payer);
            const keys = Object.keys(d.taxKeys || {}).sort();
            h += `<div class="gv-card"><h2 style="font-size:22px;color:var(--osa-text)">${esc(w.name)} <span class="dim mono" style="font-size:14px">${esc(w.id)}</span></h2>` +
                `<div class="gv-field"><label>${esc(T('payer'))}</label>${GOV.pickerBox('pick', p, m, T('search_company'))}</div>` +
                `<div class="gv-field"><label>${esc(T('multiplier'))}</label><div>${edit('wMul', w.multiplier, 'workMul', {}, { allowed: m, unit: '×', reset: 'workMulReset', shown: '×' + w.multiplier })}</div></div>` +
                `<div class="gv-field"><label>${esc(T('tax_key'))}</label><div>${m && keys.length ? select('wTax', keys.map(k => [k, `${k} (${pct(d.taxKeys[k])})`]), w.taxKey, 'workTax', true)
                    : esc(`${w.taxKey} (${pct(w.taxRate)})`)}</div></div>` +
                `<h2 style="margin-top:18px">${esc(T('params'))}</h2>` +
                table([[''], [T('default'), 'r'], [T('value'), 'r']], arr(w.params).map(prm => {
                    const v = prm.value !== undefined ? prm.value : prm.default;
                    return `<tr><td>${prm.kind === 'xp' ? '<span class="tag">XP</span> ' : ''}${esc(prm.label)}</td><td class="r mono dim">${esc(prm.default)}</td>` +
                        `<td class="r">${edit('prm_' + prm.key, v, 'workParam', { key: prm.key }, { allowed: m, reset: prm.value !== undefined ? 'workParamReset' : null })}</td></tr>`;
                })) + '</div></div>';
            return h;
        },
        actions: {
            pickWork(a) { sel.work = a.dataset.id; GOV.hidePickers(); GOV.render(); },
            workMul() { const n = numOf('wMul'); if (n !== null) GOV.change('setWork', { work: sel.work, field: 'multiplier', value: n }); },
            workMulReset() { GOV.change('setWork', { work: sel.work, field: 'multiplier' }); },
            workTax: el => GOV.change('setWork', { work: sel.work, field: 'taxKey', value: el.value }),
            workParam(b) { const n = numOf(b.dataset.input); if (n !== null) GOV.change('setWork', { work: sel.work, field: 'param', key: b.dataset.key, value: n }); },
            workParamReset(b) { GOV.change('setWork', { work: sel.work, field: 'param', key: b.dataset.key }); },
        },
        input: { workQ(el) { sel.workQ = el.value; GOV.render(); } },
    });
})();
