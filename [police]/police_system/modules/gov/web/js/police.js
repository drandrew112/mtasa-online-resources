// police_system - the "Police · Fines" page of /gov (see gov_core web/js/gov.js GOV.page).
// Every penal code amount (current value, default, reset), warnings are free; where the fine income goes.
(function () {
    'use strict';
    const { esc, arr, $, money, head, table, btn, select } = GOV.ui;
    const T = GOV.tr('police_system');

    GOV.page('police_fines', {
        keys: [...GOV.keys('police_system', ['hint', 'item', 'default', 'current', 'reset', 'save', 'target', 'target_hint',
            'changed', 'warnings_free'])],
        render(d) {
            let h = head(GOV.title('police_fines'), esc(T('hint')));
            const targets = arr(d.targets);
            h += `<div class="gv-card"><h2>${esc(T('target'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('target_hint'))}</div>` +
                `<div class="gv-row">` +
                (d.canTarget
                    ? select('pfTarget', targets.map(t => [t.code || t.value || t[0], t.name || t.label || t[1]]), d.target, '', true)
                        .replace('<select ', '<select data-keep="1" ') + btn(T('save'), 'pfTargetSave', {}, 'primary')
                    : `<b>${esc(String(d.target))}</b>`) +
                `</div></div>`;
            for (const c of arr(d.categories)) {
                if (c.warning) {
                    h += `<div class="gv-card"><h2>${esc(c.name)}</h2><div class="gv-sub">${esc(T('warnings_free'))}</div>` +
                        `<div class="gv-sub">${arr(c.items).map(i => esc(i.name)).join(' · ')}</div></div>`;
                    continue;
                }
                h += `<div class="gv-card"><h2>${esc(c.name)}</h2>` +
                    table([[T('item')], [T('default'), 'r'], [T('current'), 'r'], ['', 'act']],
                        arr(c.items).map(i => `<tr><td>${esc(i.name)}</td><td class="r mono dim">${money(i.default)}</td>` +
                            `<td class="r mono ${i.amount !== i.default ? 'pos' : ''}">${money(i.amount)}</td><td class="act">` +
                            (d.canEdit ? `<input class="osa-input num" id="pf_${esc(i.id)}" value="${i.amount}" data-keep="1"> ` +
                                btn(T('save'), 'pfSave', { id: i.id }) +
                                (i.amount !== i.default ? ' ' + btn(T('reset'), 'pfReset', { id: i.id }) : '') : '') +
                            '</td></tr>')) + '</div>';
            }
            return h;
        },
        actions: {
            async pfSave(b) {
                const id = b.dataset.id;
                const el = $('pf_' + id);
                const amount = el ? Number(String(el.value).replace(/[^\d]/g, '')) : NaN;
                if (!Number.isFinite(amount)) return;
                if (await GOV.change('setPoliceFine', { id, amount })) OSA.toast(T('changed'), true);
            },
            async pfReset(b) {
                if (await GOV.change('resetPoliceFine', { id: b.dataset.id })) OSA.toast(T('changed'), true);
            },
            async pfTargetSave() {
                const el = $('pfTarget');
                if (el && await GOV.change('setPoliceFineTarget', { code: el.value })) OSA.toast(T('changed'), true);
            },
        },
    });
})();
