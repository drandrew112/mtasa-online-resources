// gov_transport - the Public transport page of /gov (see gov_core web/js/gov.js GOV.page).
// Per mode: fares (per km, minimum, IC supplement) + who gets the ticket money; running costs
// (per IC / RB trip, per served stop) + who pays them to whom. Payer system + receiver system =
// nothing is booked.
(function () {
    'use strict';
    const { esc, arr, money, numOf, head, table, edit, payerOpts, receiverOpts, specName } = GOV.ui;
    const T = GOV.tr('gov_transport');
    const PT_MODES = ['rail'];
    const PT_NUMBERS = ['fare_km', 'fare_min', 'ic_supplement', 'cost_ic', 'cost_rb', 'cost_stop'];

    GOV.page('transport', {
        keys: [...GOV.keys('gov_transport', ['pt_fares', 'pt_fares_hint', 'pt_costs', 'pt_costs_hint', 'pt_fare_example',
            'fare_receiver', 'cost_payer', 'cost_receiver', 'pt_nothing_booked']),
            ...PT_MODES.map(k => 'gov_transport.pt.' + k), ...PT_NUMBERS.map(k => 'gov_transport.pt.' + k)],
        render(d) {
            // gov_perms: fares (per km, minimum, IC supplement) vs costs (running costs + who pays / gets the money)
            const fares = GOV.can('transport.fares.edit'), costs = GOV.can('transport.costs.edit');
            const FARES = ['fare_km', 'fare_min', 'ic_supplement'];
            let h = head(GOV.title('transport'));
            for (const md of arr(d.modes)) {
                const s = md.settings || {}, def = md.defaults || {};
                const mode = md.mode;
                const numRow = f => `<tr><td>${esc(T('gov_transport.pt.' + f))}</td><td class="r mono dim">${money(def[f])}</td>` +
                    `<td class="r">${edit(`pt_${mode}_${f}`, s[f], 'ptNum', { mode, field: f }, { allowed: FARES.includes(f) ? fares : costs, unit: '€', reset: 'ptReset', shown: money(s[f]) })}</td></tr>`;
                const spec = (f, side) => {
                    const id = `pt_${mode}_${f}`;
                    if (costs) GOV.usePicker(id, {
                        state: () => side === 'payer' ? payerOpts(d) : receiverOpts(d),
                        current: () => s[f],
                        choose: it => GOV.change('setTransport', { mode, field: f, value: it.spec }),
                    });
                    return `<div class="gv-field"><label>${esc(T(f))}</label>${GOV.pickerBox(id, specName(d, s[f], side), costs, T('search_payer'))}</div>`;
                };
                // example: a 4 km IC journey
                const km = 4, base = Math.max(Math.round(km * (s.fare_km || 0)), s.fare_min || 0);
                h += `<div class="gv-card"><h2 style="font-size:22px;color:var(--osa-text)">${esc(T('gov_transport.pt.' + mode))}</h2>` +
                    `<h2>${esc(T('pt_fares'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('pt_fares_hint'))}</div>` +
                    table([[''], [T('default'), 'r'], [T('value'), 'r']], ['fare_km', 'fare_min', 'ic_supplement'].map(numRow)) +
                    `<div class="gv-sub" style="margin:8px 0">${esc(T('pt_fare_example', { km, rb: money(base), ic: money(base + (s.ic_supplement || 0)) }))}</div>` +
                    spec('fare_receiver', 'receiver') +
                    `<h2 style="margin-top:18px">${esc(T('pt_costs'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('pt_costs_hint'))}</div>` +
                    table([[''], [T('default'), 'r'], [T('value'), 'r']], ['cost_ic', 'cost_rb', 'cost_stop'].map(numRow)) +
                    spec('cost_payer', 'payer') + spec('cost_receiver', 'receiver') +
                    (s.cost_payer === 'system' && s.cost_receiver === 'system' ? `<div class="gv-sub">${esc(T('pt_nothing_booked'))}</div>` : '') +
                    '</div>';
            }
            return h;
        },
        actions: {
            ptNum(b) { const n = numOf(b.dataset.input); if (n !== null) GOV.change('setTransport', { mode: b.dataset.mode, field: b.dataset.field, value: n }); },
            ptReset(b) { GOV.change('setTransport', { mode: b.dataset.mode, field: b.dataset.field }); },
        },
    });
})();
