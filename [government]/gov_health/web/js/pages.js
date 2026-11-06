// gov_health - the Healthcare page of /gov (see gov_core web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, $, money, val, numOf, head, empty, table, btn, edit, toggle, payerOpts, receiverOpts, specName } = GOV.ui;
    const T = GOV.tr('gov_health');
    const sel = GOV.sel;

    // who pays the treatment, per hospital: payer (system / the patient / state / private company)
    // and receiver (nobody / state / private company)
    function hospitalsCard(d) {
        const list = arr(d.hospitals);
        const hs = list.find(x => x.id === sel.hospital) || list[0];
        if (hs) sel.hospital = hs.id;
        const o = !!hs && GOV.can('health.' + hs.id + '.billing');   // gov_perms health.<hospital>.billing
        let h = `<div class="gv-card"><h2>${esc(T('hospitals'))}</h2>`;
        if (!d.hospitalsRunning) h += `<div class="gv-sub" style="margin:-6px 0 10px"><span class="tag bad">${esc(T('hospitals_offline'))}</span></div>`;
        if (!hs) return h + empty() + '</div>';
        if (o) {
            const pick = (side, opts) => GOV.usePicker(side === 'payer' ? 'hpPay' : 'hpRecv', {
                state: () => opts,
                current: () => hs[side],
                choose: it => GOV.change('setHealth', { field: 'hospital', id: hs.id, side, value: it.spec }),
            });
            pick('payer', [{ spec: 'player', name: T('patient_pays') }, ...payerOpts(d)]);
            pick('receiver', receiverOpts(d));
            // ER with staff: who pays the interventions' value, the staff salary and the stock orders
            for (const side of ['care', 'salary', 'supplies']) {
                GOV.usePicker('hp_' + side, {
                    state: () => payerOpts(d),
                    current: () => hs[side],
                    choose: it => GOV.change('setHealth', { field: 'hospital', id: hs.id, side, value: it.spec }),
                });
            }
        }
        const payer = specName(d, hs.payer, 'payer'), recv = specName(d, hs.receiver, 'receiver');
        h += `<div class="gv-split"><div class="gv-list">${list.map(x => `<a data-act="pickHospital" data-id="${esc(x.id)}" class="${x === hs ? 'on' : ''}">` +
            `<span>${esc(x.name)}</span><small>${esc(specName(d, x.payer, 'payer').name)}</small></a>`).join('')}</div>` +
            `<div><h2 style="font-size:20px;color:var(--osa-text)">${esc(hs.name)} <span class="dim mono" style="font-size:13px">${esc(hs.id)}</span></h2>` +
            (hs.missing ? `<div class="gv-sub"><span class="tag bad">${esc(T('hospital_missing'))}</span></div>` : '') +
            (!hs.missing && hs.heal === false ? `<div class="gv-sub">${esc(T('no_heal_marker'))}</div>` : '') +
            `<div class="gv-field"><label>${esc(T('payer'))}</label>${GOV.pickerBox('hpPay', payer, o, T('search_payer'))}</div>` +
            `<div class="gv-field"><label>${esc(T('receiver'))}</label>${GOV.pickerBox('hpRecv', recv, o, T('search_payer'))}</div>` +
            `<div class="gv-sub" style="margin:10px 0 4px">${esc(T('er_payers'))}</div>` +
            ['care', 'salary', 'supplies'].map(side => `<div class="gv-field"><label>${esc(T('er_' + side))}</label>` +
                `${GOV.pickerBox('hp_' + side, specName(d, hs[side], 'payer'), o, T('search_payer'))}</div>`).join('') +
            (hs.payer === 'player' ? `<div class="gv-sub">${esc(T('patient_pays_hint'))}</div>` : '') +
            (o ? `<div class="gv-field"><label></label><div>${btn(T('default_payer'), 'hospitalReset', { id: hs.id })}</div></div>` : '') +
            '</div></div>';
        return h + '</div>';
    }

    GOV.page('health', {
        keys: GOV.keys('gov_health', ['health_enabled', 'hp_price', 'injury_prices', 'add_injury', 'injury_type', 'severity_n',
            'hospitals', 'default_payer', 'hospital_missing', 'hospitals_offline', 'no_heal_marker', 'patient_pays_hint',
            'er_payers', 'er_care', 'er_salary', 'er_supplies', 'point_care', 'point_salary', 'warnings', 'warnings_none',
            'warning_row', 'clear_warnings', 'warn_care', 'warn_salary', 'warn_supplies']),
        render(d) {
            const o = GOV.can('health.prices.edit');
            const list = Object.entries(d.injuries || {}).sort((a, b) => a[0].localeCompare(b[0]));
            let h = head(GOV.title('health')) + '<div class="gv-card">' +
                `<div class="gv-field"><label>${esc(T('health_enabled'))}</label><div>${toggle(!!d.enabled, 'healthEnabled', {}, o, [T('on'), T('off')])}</div></div>` +
                `<div class="gv-field"><label>${esc(T('hp_price'))}</label><div>${edit('hpPrice', d.hpPrice, 'hpPrice', {}, { allowed: o, unit: '€', shown: money(d.hpPrice) })}</div></div>` +
                `<div class="gv-field"><label>${esc(T('point_care'))}</label><div>${edit('pointCare', d.pointCare, 'pointValue', { field: 'point_care' }, { allowed: o, unit: '€', shown: money(d.pointCare) })}</div></div>` +
                `<div class="gv-field"><label>${esc(T('point_salary'))}</label><div>${edit('pointSalary', d.pointSalary, 'pointValue', { field: 'point_salary' }, { allowed: o, unit: '€', shown: money(d.pointSalary) })}</div></div></div>` +
                // Ú9: payments the system covered because the chosen account was short
                `<div class="gv-card"><h2>${esc(T('warnings'))}</h2>` + (arr(d.warnings).length === 0 ? `<div class="gv-sub">${esc(T('warnings_none'))}</div>` :
                    arr(d.warnings).map(w => `<div class="gv-sub"><span class="tag bad">${esc(T('warn_' + w.kind))}</span> ` +
                        `${esc(T('warning_row', { hospital: w.hospital, amount: money(w.amount), at: new Date(w.at * 1000).toLocaleString() }))}</div>`).join('') +
                    (o ? `<div class="gv-row" style="margin-top:10px">${btn(T('clear_warnings'), 'clearWarnings', {})}</div>` : '')) + '</div>' +
                `<div class="gv-card"><h2>${esc(T('injury_prices'))}</h2>` +
                table([[T('injury_type')], ...[1, 2, 3].map(s => [T('severity_n', { n: s }), 'r']), ['', 'act']], list.map(([type, prices]) => {
                    prices = arr(prices);
                    return `<tr><td><b>${esc(type)}</b></td>` + [0, 1, 2].map(i => `<td class="r">${edit(`inj_${type}_${i + 1}`, prices[i] || 0, 'injury',
                        { type, sev: i + 1 }, { allowed: o, shown: money(prices[i]) })}</td>`).join('') +
                        `<td class="act">${o && type !== 'default' ? btn(T('delete'), 'removeInjury', { type }, 'danger') : ''}</td></tr>`;
                }));
            if (o) h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="newInjury" placeholder="${esc(T('injury_type'))}" maxlength="24" data-keep="1" data-enter="addInjury">${btn(T('add_injury'), 'addInjury', {}, 'primary')}</div>`;
            return hospitalsCard(d) + h + '</div>';
        },
        actions: {
            pickHospital(a) { sel.hospital = a.dataset.id; GOV.hidePickers(); GOV.render(); },
            hospitalReset(b) { GOV.change('setHealth', { field: 'hospital', id: b.dataset.id, side: 'all' }); },
            healthEnabled(b) { GOV.change('setHealth', { field: 'enabled', value: b.dataset.value === 'true' }); },
            hpPrice() { const n = numOf('hpPrice'); if (n !== null) GOV.change('setHealth', { field: 'hp_price', value: n }); },
            pointValue(b) {
                const n = numOf(b.dataset.field === 'point_care' ? 'pointCare' : 'pointSalary');
                if (n !== null) GOV.change('setHealth', { field: b.dataset.field, value: n });
            },
            clearWarnings() { GOV.change('setHealth', { field: 'clear_warnings' }); },
            injury(b) {
                const n = numOf(b.dataset.input);
                if (n !== null) GOV.change('setHealth', { field: 'injury', type: b.dataset.type, severity: Number(b.dataset.sev), value: n });
            },
            removeInjury(b) { GOV.change('setHealth', { field: 'remove_injury', type: b.dataset.type }); },
            async addInjury() {
                const t = val('newInjury').toLowerCase();
                if (t && await GOV.change('setHealth', { field: 'injury', type: t, severity: 1, value: 0 })) $('newInjury').value = '';
            },
        },
    });
})();
