// gov_tax - the Taxes and Fees pages of /gov (see gov_core web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, $, money, pct, val, numOf, head, table, btn, edit, select, runsTable } = GOV.ui;
    const T = GOV.tr('gov_tax');
    const VAT_GROUPS = ['weapons', 'clothing', 'vehicles', 'tuning', 'repair', 'services', 'real_estate'];
    const FEE_KEYS = ['register', 'rename', 'bay_fine', 'airspace.takeoff', 'airspace.landing', 'airspace.overflight'];

    // the state account a tax / fee goes to (none = the money disappears); act = taxTarget | feeTarget
    function targetPick(d, key, m, act, inline) {
        const t = arr(d.targets).find(x => x.key === key) || {};
        const opts = [['', T('tax_target_none')], ...arr(d.targetOptions).map(o => [o.code, o.name])];
        if (t.code && !opts.some(o => o[0] === t.code)) opts.push([t.code, t.code]);
        const cur = opts.find(o => o[0] === (t.code || ''));
        const pick = (m ? select(act + '_' + key.replace(/\./g, '_'), opts, t.code || '', act, true).replace('<select ', `<select data-key="${esc(key)}" `)
            : esc(cur ? cur[1] : t.code)) +
            (t.missing ? `<span class="tag bad">${esc(T('tax_target_missing'))}</span>` : '');
        return inline ? pick : `<div class="gv-field"><label>${esc(T('tax_target'))}</label><div>${pick}</div></div>`;
    }
    const taxTarget = (d, tax, m) => targetPick(d, tax, m, 'taxTarget');

    GOV.page('taxes', {
        keys: [...GOV.keys('gov_tax', ['company_tax', 'income_keys', 'add_key', 'key_name', 'vat', 'vat_hint', 'property_tax',
            'property_tax_hint', 'tax_target', 'tax_target_none', 'tax_target_missing']),
            ...VAT_GROUPS.map(g => 'gov_tax.vat.' + g), 'gov_works.page.works'],
        render(d) {
            const m = GOV.can('minister');
            const keys = Object.entries(d.keys || {}).sort((a, b) => a[0].localeCompare(b[0]));
            let h = head(GOV.title('taxes')) +
                `<div class="gv-card"><div class="gv-field"><label>${esc(T('company_tax'))}</label><div>` +
                edit('companyTax', Math.round((d.company || 0) * 1000) / 10, 'companyTax', {}, { allowed: m, unit: '%', shown: pct(d.company) }) + '</div></div>' +
                taxTarget(d, 'company', m) + '</div>' +
                `<div class="gv-card"><h2>${esc(T('income_keys'))}</h2>` + taxTarget(d, 'income', m) +
                table([[T('tax_key')], [T('gov_works.page.works')], [T('value'), 'r'], ['', 'act']], keys.map(([k, r]) =>
                    `<tr><td><b>${esc(k)}</b></td><td class="dim">${esc(arr(d.used && d.used[k]).join(', ') || '-')}</td>` +
                    `<td class="r">${edit('key_' + k, Math.round(r * 1000) / 10, 'taxKey', { key: k }, { allowed: m, unit: '%', shown: pct(r) })}</td>` +
                    `<td class="act">${m && k !== 'standard' ? btn(T('delete'), 'deleteTaxKey', { key: k }, 'danger') : ''}</td></tr>`));
            if (m) {
                h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="newKey" placeholder="${esc(T('key_name'))}" maxlength="24" data-keep="1">` +
                    `<input class="osa-input num" id="newKeyRate" placeholder="%" data-keep="1" data-enter="addTaxKey">${btn(T('add_key'), 'addTaxKey', {}, 'primary')}</div>`;
            }
            h += `</div><div class="gv-card"><h2>${esc(T('vat'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('vat_hint'))}</div>` + taxTarget(d, 'vat', m) +
                table([[T('group')], [T('default'), 'r'], [T('value'), 'r']], arr(d.vat).map(v =>
                    `<tr><td>${esc(T('gov_tax.vat.' + v.group))}</td><td class="r mono dim">${pct(v.default)}</td>` +
                    `<td class="r">${edit('vat_' + v.group, Math.round(v.rate * 1000) / 10, 'vat', { group: v.group },
                        { allowed: m, unit: '%', reset: 'vatReset', shown: pct(v.rate) })}</td></tr>`)) + '</div>' +
                `<div class="gv-card"><div class="gv-field"><label>${esc(T('property_tax'))}</label><div>` +
                edit('propTax', Math.round((d.property || 0) * 10000) / 100, 'propTax', {}, { allowed: m, unit: '%', reset: 'propTaxReset',
                    shown: (Math.round((d.property || 0) * 10000) / 100) + '%' }) +
                `<div class="gv-sub">${esc(T('property_tax_hint'))}</div></div></div>` + taxTarget(d, 'property', m) + '</div>';
            return h + `<div class="gv-card"><h2>${esc(T('tax_runs'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('history_note', { days: 30 }))}</div>${runsTable(d.runs)}</div>`;
        },
        actions: {
            companyTax() { const n = numOf('companyTax'); if (n !== null) GOV.change('setCompanyTax', { value: n }); },
            vat(b) { const n = numOf(b.dataset.input); if (n !== null) GOV.change('setVat', { group: b.dataset.group, value: n }); },
            vatReset(b) { GOV.change('setVat', { group: b.dataset.group }); },
            propTax() { const n = numOf('propTax'); if (n !== null) GOV.change('setPropertyTax', { value: n }); },
            propTaxReset() { GOV.change('setPropertyTax', {}); },
            taxTarget: el => GOV.change('setTaxTarget', { key: el.dataset.key, code: el.value }),
            taxKey(b) { const n = numOf(b.dataset.input); if (n !== null) GOV.change('setTaxKey', { key: b.dataset.key, value: n }); },
            async addTaxKey() {
                const n = numOf('newKeyRate');
                if (n === null) return;
                if (await GOV.change('setTaxKey', { key: val('newKey'), value: n })) { $('newKey').value = ''; $('newKeyRate').value = ''; }
            },
            deleteTaxKey(b) { GOV.change('deleteTaxKey', { key: b.dataset.key }); },
        },
    });

    GOV.page('fees', {
        keys: [...GOV.keys('gov_tax', ['tax_target', 'tax_target_none', 'tax_target_missing']), ...FEE_KEYS.map(k => 'gov_tax.fee.' + k)],
        render(d) {
            const m = GOV.can('minister');
            return head(GOV.title('fees')) + '<div class="gv-card">' +
                table([[''], [T('default'), 'r'], [T('value'), 'r'], [T('tax_target')]], arr(d.fees).map(f =>
                    `<tr><td>${esc(T('gov_tax.fee.' + f.key))}</td><td class="r mono dim">${money(f.default)}</td>` +
                    `<td class="r">${edit('fee_' + f.key.replace(/\./g, '_'), f.value, 'fee', { key: f.key }, { allowed: m, unit: '€', reset: 'feeReset', shown: money(f.value) })}</td>` +
                    `<td>${targetPick(d, f.key, m, 'feeTarget', true)}</td></tr>`)) + '</div>';
        },
        actions: {
            feeTarget: el => GOV.change('setFeeTarget', { key: el.dataset.key, code: el.value }),
            fee(b) { const n = numOf(b.dataset.input); if (n !== null) GOV.change('setFee', { key: b.dataset.key, value: n }); },
            feeReset(b) { GOV.change('setFee', { key: b.dataset.key }); },
        },
    });
})();
