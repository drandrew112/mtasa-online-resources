// gov_treasury - the Overview, Treasury, Transfers and Budget pages of /gov (see gov_core
// web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, $, money, signed, cls, stamp, val, numOf, head, kpi, empty, table, btn, select, runsTable } = GOV.ui;
    const T = GOV.tr('gov_treasury');
    const D = GOV.D, sel = GOV.sel;
    const GROUPS = ['all', 'tax', 'fine', 'health', 'work', 'biz', 'gov', 'atc', 'pt', 'loan', 'transfer', 'admin'];
    const GROUP_KEYS = [...GROUPS, 'shop', 'cash', 'other'].map(g => 'v_bank.group.' + g);
    sel.group = sel.group || 'all';
    sel.soKind = sel.soKind || 'state';

    function groupSums(stats) {
        const g = {};
        for (const [key, s] of Object.entries(stats || {})) {
            const name = key.split('.')[0];
            g[name] = g[name] || { inSum: 0, outSum: 0 };
            g[name].inSum += Number(s.inSum) || 0;
            g[name].outSum += Number(s.outSum) || 0;
        }
        return Object.entries(g).sort((a, b) => a[0].localeCompare(b[0]));
    }
    const sumOf = (stats, f) => groupSums(stats).reduce((t, [, s]) => t + s[f], 0);

    // ------------------------------------------------------------ Overview
    GOV.page('overview', {
        keys: [...GOV.keys('gov_treasury', ['treasury_balance', 'last_24h', 'last_7d', 'state_accounts']), ...GROUP_KEYS],
        render(d) {
            const t = d.treasury || {};
            const groups = (stats) => table([[T('group')], [T('income'), 'r'], [T('expense'), 'r']], groupSums(stats).map(([n, s]) =>
                `<tr><td>${esc(T('v_bank.group.' + n))}</td><td class="r mono pos">+${money(s.inSum)}</td><td class="r mono neg">-${money(s.outSum)}</td></tr>`));
            return head(GOV.title('overview')) +
                `<div class="gv-kpis">${kpi(T('treasury_balance'), money(t.balance), cls(t.balance))}` +
                kpi(T('last_24h'), signed(sumOf(d.day, 'inSum') - sumOf(d.day, 'outSum')), cls(sumOf(d.day, 'inSum') - sumOf(d.day, 'outSum'))) +
                kpi(T('last_7d'), signed(sumOf(d.week, 'inSum') - sumOf(d.week, 'outSum')), cls(sumOf(d.week, 'inSum') - sumOf(d.week, 'outSum'))) + '</div>' +
                `<div class="gv-grid2"><div class="gv-card"><h2>${esc(T('last_24h'))}</h2>${groups(d.day)}</div>` +
                `<div class="gv-card"><h2>${esc(T('last_7d'))}</h2>${groups(d.week)}</div></div>` +
                `<div class="gv-grid2"><div class="gv-card"><h2>${esc(T('state_accounts'))}</h2>` +
                table([[T('account')], [T('balance'), 'r']], arr(d.states).filter(s => s.status !== 'closed').map(s =>
                    `<tr><td>${esc(s.name)} <span class="dim mono">${esc(s.number || '')}</span></td><td class="r mono ${cls(s.balance)}">${money(s.balance)}</td></tr>`)) +
                `</div><div class="gv-card"><h2>${esc(T('tax_runs'))}</h2>${runsTable(d.runs)}</div></div>`;
        },
    });

    // ------------------------------------------------------------ Treasury (statements)
    GOV.page('treasury', {
        keys: [...GOV.keys('gov_treasury', ['from_treasury', 'to_treasury', 'older']), ...GROUP_KEYS],
        async load() {
            if (!D.overview) D.overview = await GOV.call('overview');
            const r = await GOV.call('treasuryLedger', { id: sel.treasury || undefined, group: sel.group !== 'all' ? sel.group : undefined });
            sel.treasury = r.id;
            return r;
        },
        render(d) {
            const states = arr(D.overview && D.overview.states).filter(s => s.status !== 'closed');
            const cur = states.find(s => s.id === d.id);
            let h = head(GOV.title('treasury'), esc(T('history_note', { days: 30 })), cur ? `<div class="big ${cls(cur.balance)}">${money(cur.balance)}</div>` : '') +
                `<div class="gv-row">${select('trAcc', states.map(s => [s.id, s.name]), d.id, 'trAcc', true)}` +
                select('trGroup', GROUPS.map(g => [g, T('v_bank.group.' + g)]), sel.group, 'trGroup', true) + '</div>';
            if (GOV.can('minister') && cur && cur.ownerRef !== 'treasury') {
                h += `<div class="gv-card"><div class="gv-row"><input class="osa-input num" id="trAmount" placeholder="${esc(T('amount'))}" data-keep="1">` +
                    `<input class="osa-input mid" id="trNote" placeholder="${esc(T('note'))}" maxlength="60" data-keep="1">` +
                    btn(T('from_treasury'), 'transfer', { dir: 'to' }, 'primary') + btn(T('to_treasury'), 'transfer', { dir: 'from' }) + '</div></div>';
            }
            h += `<div class="gv-card">` + table([[T('time')], [T('description')], [T('amount'), 'r'], [T('balance'), 'r']], arr(d.rows).map(r => {
                let txt = esc(r.text || r.key);
                if (r.counter && r.counter.number) txt += ` <span class="dim">· ${esc(r.counter.name)}</span>`;
                if (r.params && r.params.note) txt += ` <span class="dim">· ${esc(r.params.note)}</span>`;
                return `<tr><td class="mono dim">${stamp(r.ts)}</td><td>${txt}</td><td class="r mono ${cls(r.amount)}">${signed(r.amount)}</td>` +
                    `<td class="r mono dim">${r.balance !== undefined ? money(r.balance) : '-'}</td></tr>`;
            }));
            if (d.more) h += `<div class="gv-row" style="justify-content:flex-end;margin-top:12px">${btn(T('older'), 'older')}</div>`;
            return h + '</div>';
        },
        actions: {
            trAcc: el => { sel.treasury = Number(el.value); GOV.load('treasury'); },
            trGroup: el => { sel.group = el.value; GOV.load('treasury'); },
            async transfer(b) {
                const n = numOf('trAmount');
                if (n === null) return;
                if (await GOV.change('treasuryTransfer', { id: sel.treasury, amount: n, dir: b.dataset.dir, note: val('trNote') })) {
                    $('trAmount') && ($('trAmount').value = '');
                    $('trNote') && ($('trNote').value = '');
                    D.overview = await GOV.call('overview').catch(() => D.overview);
                    GOV.render();
                }
            },
            async older() {
                const d = D.treasury;
                const rows = arr(d.rows);
                const last = rows[rows.length - 1];
                try {
                    const r = await GOV.call('treasuryLedger', { id: d.id, before: last && last.id, group: sel.group !== 'all' ? sel.group : undefined });
                    d.rows = rows.concat(arr(r.rows));
                    d.more = r.more;
                    GOV.render();
                } catch (e) { OSA.toast(e.message, false); }
            },
        },
    });

    // ------------------------------------------------------------ Transfers + standing orders
    GOV.page('transfers', {
        keys: GOV.keys('gov_treasury', ['tf_state', 'tf_pay', 'tf_collect', 'tf_collect_hint', 'tf_from', 'tf_to', 'tf_send', 'tf_pay_btn',
            'tf_collect_btn', 'tf_recent', 'tf_kind', 'tf_pick_company', 'confirm_transfer',
            'so_title', 'so_hint', 'so_every', 'so_hours', 'so_days', 'so_create', 'so_next', 'so_last', 'so_runs',
            'so_pause', 'so_resume', 'so_paused', 'confirm_delete_so', 'so_edit', 'so_editing', 'so_save', 'so_cancel']),
        render(d) {
            const m = GOV.can('minister');
            const states = arr(d.states).filter(s => s.status !== 'closed');
            const opts = states.map(s => [s.id, `${s.name} (${money(s.balance)})`]);
            const amountNote = k => `<input class="osa-input num" id="${k}Amount" placeholder="${esc(T('amount'))}" data-keep="1">` +
                `<input class="osa-input mid" id="${k}Note" placeholder="${esc(T('note'))}" maxlength="48" data-keep="1">`;
            const keepSel = (id, v) => select(id, opts, v, '', true).replace('<select ', '<select data-keep="1" ');
            const kindName = a => T({ 'transfer.state': 'tf_state', 'transfer.pay': 'tf_pay', 'transfer.collect': 'tf_collect' }[a] || a);
            const coName = c => c ? { name: c.name, tag: 'company' } : { name: T('tf_pick_company'), tag: '' };
            let h = head(GOV.title('transfers'), esc(T('history_note', { days: 30 })));
            if (m) {
                GOV.usePicker('tfPay', { state: () => [], current: () => sel.tfPay && sel.tfPay.spec, choose: it => { sel.tfPay = it; GOV.render(); } });
                GOV.usePicker('tfCol', { state: () => [], current: () => sel.tfCol && sel.tfCol.spec, choose: it => { sel.tfCol = it; GOV.render(); } });
                const first = states[0] && states[0].id, second = states[1] ? states[1].id : first;
                h += `<div class="gv-card"><h2>${esc(T('tf_state'))}</h2><div class="gv-row">` +
                    `<label class="dim">${esc(T('tf_from'))}</label>${keepSel('tfsFrom', first)}<label class="dim">${esc(T('tf_to'))}</label>${keepSel('tfsTo', second)}</div>` +
                    `<div class="gv-row" style="margin-top:10px">${amountNote('tfs')}${btn(T('tf_send'), 'tfSend', { kind: 'state' }, 'primary')}</div></div>` +
                    `<div class="gv-card"><h2>${esc(T('tf_pay'))}</h2><div class="gv-field"><label>${esc(T('tf_from'))}</label><div>${keepSel('tfpFrom', first)}</div></div>` +
                    `<div class="gv-field"><label>${esc(T('tf_to'))}</label>${GOV.pickerBox('tfPay', coName(sel.tfPay), true, T('search_private'))}</div>` +
                    `<div class="gv-row" style="margin-top:10px">${amountNote('tfp')}${btn(T('tf_pay_btn'), 'tfSend', { kind: 'pay' }, 'primary')}</div></div>` +
                    `<div class="gv-card"><h2>${esc(T('tf_collect'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('tf_collect_hint'))}</div>` +
                    `<div class="gv-field"><label>${esc(T('tf_from'))}</label>${GOV.pickerBox('tfCol', coName(sel.tfCol), true, T('search_private'))}</div>` +
                    `<div class="gv-field"><label>${esc(T('tf_to'))}</label><div>${keepSel('tfcTo', first)}</div></div>` +
                    `<div class="gv-row" style="margin-top:10px">${amountNote('tfc')}${btn(T('tf_collect_btn'), 'tfSend', { kind: 'collect' }, 'danger')}</div></div>`;
            } else {
                h += `<div class="gv-card">` + table([[T('account')], [T('balance'), 'r']], states.map(s =>
                    `<tr><td>${esc(s.name)} <span class="dim mono">${esc(s.number || '')}</span></td><td class="r mono ${cls(s.balance)}">${money(s.balance)}</td></tr>`)) + '</div>';
            }
            const every = sec => sec % 86400 === 0 ? `${sec / 86400} ${T('so_days')}` : `${Math.round(sec / 360) / 10} ${T('so_hours')}`;
            const orders = arr(d.orders);
            h += `<div class="gv-card"><h2>${esc(T('so_title'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('so_hint'))}</div>`;
            if (sel.soEdit && !orders.some(o => o.id === sel.soEdit)) sel.soEdit = null;   // deleted meanwhile
            if (m) {
                GOV.usePicker('soCo', { state: () => [], current: () => sel.soCo && sel.soCo.spec, choose: it => { sel.soCo = it; GOV.render(); } });
                const k = sel.soKind;
                const first = states[0] && states[0].id, second = states[1] ? states[1].id : first;
                h += `<div class="gv-row">${select('soKind', [['state', T('tf_state')], ['pay', T('tf_pay')], ['collect', T('tf_collect')]], k, 'soKind', true)}` +
                    (sel.soEdit ? `<b>${esc(T('so_editing', { id: sel.soEdit }))}</b>` : '') + '</div>' +
                    `<div class="gv-row" style="margin-top:10px"><label class="dim">${esc(T('tf_from'))}</label>` +
                    (k === 'collect' ? GOV.pickerBox('soCo', coName(sel.soCo), true, T('search_private')) : keepSel('soFrom', first)) +
                    `<label class="dim">${esc(T('tf_to'))}</label>` +
                    (k === 'pay' ? GOV.pickerBox('soCo', coName(sel.soCo), true, T('search_private')) : keepSel('soTo', k === 'state' ? second : first)) + '</div>' +
                    `<div class="gv-row" style="margin-top:10px">${amountNote('so')}<label class="dim">${esc(T('so_every'))}</label>` +
                    `<input class="osa-input num" id="soEvery" value="1" data-keep="1">` +
                    select('soUnit', [['3600', T('so_hours')], ['86400', T('so_days')]], '86400', '', true).replace('<select ', '<select data-keep="1" ') +
                    (sel.soEdit ? btn(T('so_save'), 'soCreate', {}, 'primary') + btn(T('so_cancel'), 'soCancel')
                        : btn(T('so_create'), 'soCreate', {}, 'primary')) + '</div>';
            }
            h += table([[T('tf_kind')], [T('tf_from')], [T('tf_to')], [T('amount'), 'r'], [T('so_every')], [T('so_next')], [T('so_last')], [T('note')], ['', 'act']],
                orders.map(o => `<tr${o.enabled ? '' : ' class="dim"'}${o.id === sel.soEdit ? ' style="outline:1px solid currentColor"' : ''}><td>${esc(kindName('transfer.' + o.kind))}</td><td>${esc(o.fromName)}</td><td>${esc(o.toName)}</td>` +
                    `<td class="r mono">${money(o.amount)}</td><td>${esc(every(o.interval))}</td>` +
                    `<td class="mono dim">${o.enabled ? stamp(o.nextRun) : esc(T('so_paused'))}</td>` +
                    `<td class="dim">${o.lastRun ? `${stamp(o.lastRun)} ${esc(o.lastStatus)}` : '-'} (${esc(T('so_runs'))}: ${o.runs})</td><td class="dim">${esc(o.note)}</td>` +
                    `<td class="act">${m ? btn(T('so_edit'), 'soEdit', { id: o.id }) + ' ' +
                        btn(T(o.enabled ? 'so_pause' : 'so_resume'), 'soToggle', { id: o.id, value: o.enabled ? 'false' : 'true' }) +
                        ' ' + btn(T('delete'), 'soDelete', { id: o.id }, 'danger') : ''}</td></tr>`)) + '</div>';
            return h + `<div class="gv-card"><h2>${esc(T('tf_recent'))}</h2>` +
                table([[T('time')], [T('tf_kind')], [T('tf_from')], [T('tf_to')], [T('amount'), 'r'], [T('note')], [T('actor')]], arr(d.list).map(r => {
                    const x = r.detail || {};
                    return `<tr><td class="mono dim">${stamp(r.ts)}</td><td>${esc(kindName(r.action))}</td><td>${esc(x.from ?? '')}</td><td>${esc(x.to ?? '')}</td>` +
                        `<td class="r mono">${money(x.amount)}</td><td class="dim">${esc(x.note || '')}</td><td><b>${esc(r.actor)}</b></td></tr>`;
                })) + '</div>';
        },
        actions: {
            async tfSend(b) {
                const kind = b.dataset.kind;
                const k = { state: 'tfs', pay: 'tfp', collect: 'tfc' }[kind];
                const n = numOf(k + 'Amount');
                if (n === null) return;
                const args = { kind, amount: n, note: val(k + 'Note') };
                const stateName = id => { const s = arr((D.transfers || {}).states).find(x => String(x.id) === String(id)); return s ? s.name : id; };
                let from, to;
                if (kind === 'state') { args.from = Number(val('tfsFrom')); args.to = Number(val('tfsTo')); from = stateName(args.from); to = stateName(args.to); }
                else if (kind === 'pay') {
                    if (!sel.tfPay) return OSA.toast(T('tf_pick_company'), false);
                    args.from = Number(val('tfpFrom')); args.to = Number(sel.tfPay.spec.split(':')[1]); from = stateName(args.from); to = sel.tfPay.name;
                } else {
                    if (!sel.tfCol) return OSA.toast(T('tf_pick_company'), false);
                    args.from = Number(sel.tfCol.spec.split(':')[1]); args.to = Number(val('tfcTo')); from = sel.tfCol.name; to = stateName(args.to);
                }
                if (!await OSA.ui.confirm(GOV.title('transfers'), T('confirm_transfer', { amount: money(n), from, to }), T('save'))) return;
                if (await GOV.change('moneyTransfer', args)) {
                    $(k + 'Amount') && ($(k + 'Amount').value = '');
                    $(k + 'Note') && ($(k + 'Note').value = '');
                }
            },
            soKind: el => { sel.soKind = el.value; sel.soCo = null; GOV.render(); },
            async soCreate() {
                const n = numOf('soAmount'), ev = numOf('soEvery');
                if (n === null || ev === null) return;
                const kind = sel.soKind;
                const states = arr((D.transfers || {}).states);
                const stateName = id => { const x = states.find(y => String(y.id) === String(id)); return x ? x.name : id; };
                const args = { kind, amount: n, note: val('soNote'), interval: Math.round(ev * Number(val('soUnit'))) };
                let from, to;
                if (kind !== 'state' && !sel.soCo) return OSA.toast(T('tf_pick_company'), false);
                if (kind === 'collect') { args.from = Number(sel.soCo.spec.split(':')[1]); args.to = Number(val('soTo')); from = sel.soCo.name; to = stateName(args.to); }
                else if (kind === 'pay') { args.from = Number(val('soFrom')); args.to = Number(sel.soCo.spec.split(':')[1]); from = stateName(args.from); to = sel.soCo.name; }
                else { args.from = Number(val('soFrom')); args.to = Number(val('soTo')); from = stateName(args.from); to = stateName(args.to); }
                const per = ev + ' ' + (val('soUnit') === '3600' ? T('so_hours') : T('so_days'));
                if (sel.soEdit) args.id = sel.soEdit;
                if (!await OSA.ui.confirm(T('so_title'), T('confirm_transfer', { amount: money(n), from, to }) + ' / ' + per, T('save'))) return;
                if (await GOV.change(args.id ? 'updateStanding' : 'createStanding', args)) {
                    sel.soEdit = null;
                    $('soAmount') && ($('soAmount').value = '');
                    $('soNote') && ($('soNote').value = '');
                    GOV.render();
                }
            },
            // loads an order into the form above; Save then edits it (updateStanding)
            soEdit(b) {
                const o = arr((D.transfers || {}).orders).find(x => x.id === Number(b.dataset.id));
                if (!o) return;
                sel.soEdit = o.id;
                sel.soKind = o.kind;
                sel.soCo = o.kind === 'pay' ? { spec: 'company:' + o.to, name: o.toName }
                    : o.kind === 'collect' ? { spec: 'company:' + o.from, name: o.fromName } : null;
                GOV.render();
                const set = (id, v) => { const el = $(id); if (el) el.value = v; };
                if (o.kind !== 'collect') set('soFrom', o.from);
                if (o.kind !== 'pay') set('soTo', o.to);
                const days = o.interval % 86400 === 0;
                set('soUnit', days ? '86400' : '3600');
                set('soEvery', days ? o.interval / 86400 : Math.round(o.interval / 36) / 100);
                set('soAmount', o.amount);
                set('soNote', o.note);
                $('soKind') && $('soKind').scrollIntoView({ block: 'center' });
            },
            soCancel() {
                sel.soEdit = null;
                $('soAmount') && ($('soAmount').value = '');
                $('soNote') && ($('soNote').value = '');
                GOV.render();
            },
            soToggle(b) { GOV.change('toggleStanding', { id: Number(b.dataset.id), enabled: b.dataset.value === 'true' }); },
            async soDelete(b) {
                if (await OSA.ui.confirm(T('so_title'), T('confirm_delete_so'), T('delete'))) GOV.change('deleteStanding', { id: Number(b.dataset.id) });
            },
        },
    });

    // ------------------------------------------------------------ Budget
    GOV.page('budget', {
        keys: [...GOV.keys('gov_treasury', ['daily']), ...GROUP_KEYS],
        render(d) {
            const rows = arr(d.rows);
            const daily = arr(d.daily);
            const max = Math.max(1, ...daily.map(x => Math.max(x.inSum, x.outSum)));
            const bars = daily.length ? `<div class="gv-bars">${daily.map(x => `<div class="gv-bar" title="${esc(new Date(x.day * 1000).toLocaleDateString('en-GB'))}: +${money(x.inSum)} / -${money(x.outSum)}">` +
                `<i class="in" style="height:${Math.round(x.inSum / max * 100)}%"></i><i class="out" style="height:${Math.round(x.outSum / max * 100)}%"></i></div>`).join('')}</div>` : empty();
            return head(GOV.title('budget'), esc(T('history_note', { days: d.days || 30 }))) +
                `<div class="gv-card"><h2>${esc(T('daily'))} · ${esc(rows[0] ? rows[0].name : '')}</h2>${bars}</div>` +
                rows.map(r => `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(r.name)}</h2><div class="gv-sub mono">${esc(r.code)}</div></div>` +
                    `<div class="gv-row"><span class="mono pos">+${money(r.inSum)}</span><span class="mono neg">-${money(r.outSum)}</span>` +
                    `<b class="mono ${cls(r.inSum - r.outSum)}">${signed(r.inSum - r.outSum)}</b></div></div>` +
                    table([[T('group')], [T('income'), 'r'], [T('expense'), 'r'], [T('net'), 'r']], arr(r.groups).map(g =>
                        `<tr><td>${esc(T('v_bank.group.' + g.group))}</td><td class="r mono pos">+${money(g.inSum)}</td><td class="r mono neg">-${money(g.outSum)}</td>` +
                        `<td class="r mono ${cls(g.inSum - g.outSum)}">${signed(g.inSum - g.outSum)}</td></tr>`)) + '</div>').join('');
        },
    });
})();
