// gov_treasury - the Overview, Treasury, Transfers, Budget and Budget plan pages of /gov (see gov_core
// web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, $, money, signed, cls, stamp, val, numOf, head, kpi, empty, table, btn, select, runsTable } = GOV.ui;
    const T = GOV.tr('gov_treasury');
    const D = GOV.D, sel = GOV.sel;
    const GROUPS = ['all', 'tax', 'fine', 'health', 'work', 'salary', 'biz', 'gov', 'atc', 'pt', 'loan', 'transfer', 'admin'];
    // the rights of a state account (target = "treasury" | state company id, gov_perms)
    const canAcc = (s, right) => !!s && !!s.target && GOV.can('gov.' + s.target + '.' + right);
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
            const r = await GOV.call('treasuryLedger', { id: sel.treasury || undefined, group: sel.group !== 'all' ? sel.group : undefined });
            sel.treasury = r.id;
            return r;
        },
        render(d) {
            const states = arr(d.states).filter(s => s.status !== 'closed');
            const cur = states.find(s => s.id === d.id);
            const treasury = { target: 'treasury' };
            let h = head(GOV.title('treasury'), esc(T('history_note', { days: 30 })), cur ? `<div class="big ${cls(cur.balance)}">${money(cur.balance)}</div>` : '') +
                `<div class="gv-row">${select('trAcc', states.map(s => [s.id, s.name]), d.id, 'trAcc', true)}` +
                select('trGroup', GROUPS.map(g => [g, T('v_bank.group.' + g)]), sel.group, 'trGroup', true) + '</div>';
            const toCur = canAcc(treasury, 'bank.pay'), fromCur = canAcc(cur, 'bank.pay');
            if (cur && cur.ownerRef !== 'treasury' && (toCur || fromCur)) {
                h += `<div class="gv-card"><div class="gv-row"><input class="osa-input num" id="trAmount" placeholder="${esc(T('amount'))}" data-keep="1">` +
                    `<input class="osa-input mid" id="trNote" placeholder="${esc(T('note'))}" maxlength="60" data-keep="1">` +
                    (toCur ? btn(T('from_treasury'), 'transfer', { dir: 'to' }, 'primary') : '') +
                    (fromCur ? btn(T('to_treasury'), 'transfer', { dir: 'from' }) : '') + '</div></div>';
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
            const states = arr(d.states).filter(s => s.status !== 'closed');
            const all = arr(d.all);
            const balance = id => { const s = states.find(x => x.id === id); return s ? ` (${money(s.balance)})` : ''; };
            // from: the accounts the player may pay from / make orders of; to: every state account
            const payable = all.filter(s => canAcc(s, 'bank.pay'));
            const standable = all.filter(s => canAcc(s, 'standing'));
            const fromOpts = list => list.map(s => [s.id, s.name + balance(s.id)]);
            const opts = fromOpts(all);
            const m = payable.length > 0 || d.collect;
            const amountNote = k => `<input class="osa-input num" id="${k}Amount" placeholder="${esc(T('amount'))}" data-keep="1">` +
                `<input class="osa-input mid" id="${k}Note" placeholder="${esc(T('note'))}" maxlength="48" data-keep="1">`;
            const keepSel = (id, v, list) => select(id, list || opts, v, '', true).replace('<select ', '<select data-keep="1" ');
            const kindName = a => T({ 'transfer.state': 'tf_state', 'transfer.pay': 'tf_pay', 'transfer.collect': 'tf_collect' }[a] || a);
            const coName = c => c ? { name: c.name, tag: 'company' } : { name: T('tf_pick_company'), tag: '' };
            let h = head(GOV.title('transfers'), esc(T('history_note', { days: 30 })));
            if (m) {
                GOV.usePicker('tfPay', { state: () => [], current: () => sel.tfPay && sel.tfPay.spec, choose: it => { sel.tfPay = it; GOV.render(); } });
                GOV.usePicker('tfCol', { state: () => [], current: () => sel.tfCol && sel.tfCol.spec, choose: it => { sel.tfCol = it; GOV.render(); } });
                const first = payable[0] && payable[0].id;
                const second = (all.find(s => s.id !== first) || {}).id || first;
                if (payable.length) {
                    h += `<div class="gv-card"><h2>${esc(T('tf_state'))}</h2><div class="gv-row">` +
                        `<label class="dim">${esc(T('tf_from'))}</label>${keepSel('tfsFrom', first, fromOpts(payable))}<label class="dim">${esc(T('tf_to'))}</label>${keepSel('tfsTo', second)}</div>` +
                        `<div class="gv-row" style="margin-top:10px">${amountNote('tfs')}${btn(T('tf_send'), 'tfSend', { kind: 'state' }, 'primary')}</div></div>`;
                }
                if (payable.length && d.payCompany) {
                    h += `<div class="gv-card"><h2>${esc(T('tf_pay'))}</h2><div class="gv-field"><label>${esc(T('tf_from'))}</label><div>${keepSel('tfpFrom', first, fromOpts(payable))}</div></div>` +
                        `<div class="gv-field"><label>${esc(T('tf_to'))}</label>${GOV.pickerBox('tfPay', coName(sel.tfPay), true, T('search_private'))}</div>` +
                        `<div class="gv-row" style="margin-top:10px">${amountNote('tfp')}${btn(T('tf_pay_btn'), 'tfSend', { kind: 'pay' }, 'primary')}</div></div>`;
                }
                if (d.collect) {
                    h += `<div class="gv-card"><h2>${esc(T('tf_collect'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('tf_collect_hint'))}</div>` +
                        `<div class="gv-field"><label>${esc(T('tf_from'))}</label>${GOV.pickerBox('tfCol', coName(sel.tfCol), true, T('search_private'))}</div>` +
                        `<div class="gv-field"><label>${esc(T('tf_to'))}</label><div>${keepSel('tfcTo', all[0] && all[0].id)}</div></div>` +
                        `<div class="gv-row" style="margin-top:10px">${amountNote('tfc')}${btn(T('tf_collect_btn'), 'tfSend', { kind: 'collect' }, 'danger')}</div></div>`;
                }
            }
            if (states.length) {
                h += `<div class="gv-card">` + table([[T('account')], [T('balance'), 'r']], states.map(s =>
                    `<tr><td>${esc(s.name)} <span class="dim mono">${esc(s.number || '')}</span></td><td class="r mono ${cls(s.balance)}">${money(s.balance)}</td></tr>`)) + '</div>';
            }
            const every = sec => sec % 86400 === 0 ? `${sec / 86400} ${T('so_days')}` : `${Math.round(sec / 360) / 10} ${T('so_hours')}`;
            const orders = arr(d.orders);
            h += `<div class="gv-card"><h2>${esc(T('so_title'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('so_hint'))}</div>`;
            if (sel.soEdit && !orders.some(o => o.id === sel.soEdit)) sel.soEdit = null;   // deleted meanwhile
            // the kinds of orders the player may make: state (gov.<from>.standing), pay (+ treasury.transfer.company), collect
            const soKinds = [...(standable.length ? [['state', T('tf_state')]] : []), ...(standable.length && d.payCompany ? [['pay', T('tf_pay')]] : []),
                ...(d.collect ? [['collect', T('tf_collect')]] : [])];
            if (!soKinds.some(x => x[0] === sel.soKind) && soKinds.length) sel.soKind = soKinds[0][0];
            const canOrder = o => o.kind === 'collect' ? !!d.collect
                : (o.kind !== 'pay' || d.payCompany) && canAcc(all.find(s => s.id === o.from), 'standing');
            if (soKinds.length) {
                GOV.usePicker('soCo', { state: () => [], current: () => sel.soCo && sel.soCo.spec, choose: it => { sel.soCo = it; GOV.render(); } });
                const k = sel.soKind;
                const first = standable[0] && standable[0].id;
                const second = (all.find(s => s.id !== first) || {}).id || first;
                h += `<div class="gv-row">${select('soKind', soKinds, k, 'soKind', true)}` +
                    (sel.soEdit ? `<b>${esc(T('so_editing', { id: sel.soEdit }))}</b>` : '') + '</div>' +
                    `<div class="gv-row" style="margin-top:10px"><label class="dim">${esc(T('tf_from'))}</label>` +
                    (k === 'collect' ? GOV.pickerBox('soCo', coName(sel.soCo), true, T('search_private')) : keepSel('soFrom', first, fromOpts(standable))) +
                    `<label class="dim">${esc(T('tf_to'))}</label>` +
                    (k === 'pay' ? GOV.pickerBox('soCo', coName(sel.soCo), true, T('search_private')) : keepSel('soTo', k === 'state' ? second : all[0] && all[0].id)) + '</div>' +
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
                    `<td class="act">${canOrder(o) ? btn(T('so_edit'), 'soEdit', { id: o.id }) + ' ' +
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
                const stateName = id => { const s = arr((D.transfers || {}).all).find(x => String(x.id) === String(id)); return s ? s.name : id; };
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
                const states = arr((D.transfers || {}).all);
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

    // ------------------------------------------------------------ Budget plan
    // A 24-hour plan for every day of the week (the next 7 days, Monday first): one for the whole
    // state, then one per state account (treasury + every state company). Rows: plan items of the
    // minister, standing orders, the railway running costs (timetable × cost settings).
    const PLAN_KEYS = ['plan_hint', 'plan_income', 'plan_expense', 'plan_net', 'plan_week', 'plan_items', 'plan_items_hint',
        'plan_item_name', 'plan_kind', 'plan_kind_income', 'plan_kind_expense', 'plan_add', 'plan_save', 'plan_cancel', 'plan_editing',
        'plan_fill', 'plan_edit', 'plan_rail', 'plan_rail_detail', 'plan_rail_hint', 'plan_rail_trips', 'plan_rail_stops', 'plan_rail_run',
        'plan_rail_stop', 'plan_rail_total', 'plan_rail_flow', 'plan_rail_not_state', 'plan_rail_none', 'plan_rail_offline',
        'plan_today', 'confirm_delete_plan', 'plan_none', 'plan_whole', 'plan_whole_hint', 'plan_account', 'plan_internal',
        'plan_internal_hint', 'plan_so_to', 'plan_so_from', 'plan_empty_account', 'plan_rail_internal', 'plan_salary', 'plan_salary_hint',
        'day_1', 'day_2', 'day_3', 'day_4', 'day_5', 'day_6', 'day_7'];
    const stateCode = spec => (String(spec || '').match(/^state:(.+)$/) || [])[1] || null;

    GOV.page('budgetPlan', {
        keys: [...GOV.keys('gov_treasury', PLAN_KEYS), 'gov_treasury.err.bad_plan_kind'],
        render(d) {
            const m = GOV.can('treasury.plan.edit');
            const days = arr(d.days).slice().sort((a, b) => a.weekday - b.weekday);
            // salaries of the positions (gov_perms): an expense of the treasury, one row per position
            const salaryNames = [...new Set(days.flatMap(x => Object.keys((x.salary && x.salary.groups) || {})))].sort();
            const today = arr(d.days)[0];
            const accounts = arr(d.accounts);
            const items = arr(d.items);
            const orders = arr(d.orders);
            const accName = code => (accounts.find(a => a.code === code) || {}).name || code;
            const itemAcc = i => i.account || 'treasury';
            const amt = (it, day) => Number(arr(it.amounts)[day.weekday - 1]) || 0;
            const orderAmt = (o, day) => Number((day.orders || {})[String(o.id)]) || 0;
            const specLabel = spec => spec === 'system' ? '-' : GOV.ui.payerName(d, spec).name;
            const note = s => s ? ` <span class="dim">${esc(s)}</span>` : '';

            const rail0 = today && today.rail;
            const anyRail = days.some(x => x.rail);
            const railPayer = rail0 && rail0.booked ? stateCode(rail0.payer) : null;
            const railReceiver = rail0 && rail0.booked ? stateCode(rail0.receiver) : null;
            const railTotal = x => x.rail ? x.rail.total || 0 : 0;
            const railNote = !anyRail ? T('plan_rail_offline') : !rail0.booked ? T('plan_rail_none')
                : T('plan_rail_flow', { payer: specLabel(rail0.payer), receiver: specLabel(rail0.receiver) });

            const colHead = [[''], ...days.map(x => [`${T('day_' + x.weekday)} ${x.date.slice(5).replace('-', '.')}${today && x.ts === today.ts ? ' · ' + T('plan_today') : ''}`, 'r']), [T('plan_week'), 'r']];
            const cells = (f, sign, c) => {
                let sum = 0;
                const tds = days.map(x => { const v = f(x); sum += v; return `<td class="r mono ${v ? c : 'dim'}">${v ? sign + money(v) : '-'}</td>`; }).join('');
                return tds + `<td class="r mono ${sum ? c : 'dim'}"><b>${sum ? sign + money(sum) : '-'}</b></td>`;
            };
            const sec = label => `<tr><td colspan="${days.length + 2}" class="dim" style="padding-top:12px"><b>${esc(label)}</b></td></tr>`;

            // the rows of a plan: { label (html), f(day), side: in | out | info }; code = null -> the whole state
            function planRows(code) {
                const rows = [];
                for (const i of items) {
                    if (code && itemAcc(i) !== code) continue;
                    rows.push({ label: esc(i.name) + note(code ? i.note : `${accName(itemAcc(i))}${i.note ? ' · ' + i.note : ''}`), f: x => amt(i, x), side: i.kind === 'income' ? 'in' : 'out' });
                }
                for (const o of orders) {
                    const to = `${T('plan_so_to', { name: o.toName || '?' })}${o.note ? ' · ' + o.note : ''}`;
                    const from = `${T('plan_so_from', { name: o.fromName || '?' })}${o.note ? ' · ' + o.note : ''}`;
                    const f = x => orderAmt(o, x);
                    if (code) {
                        if (o.fromCode === code) rows.push({ label: esc(to), f, side: 'out' });
                        if (o.toCode === code) rows.push({ label: esc(from), f, side: 'in' });
                    } else if (o.kind === 'pay') rows.push({ label: esc(to), f, side: 'out' });
                    else if (o.kind === 'collect') rows.push({ label: esc(from), f, side: 'in' });
                }
                if (!code) {
                    const internal = orders.filter(o => o.kind === 'state');
                    if (internal.length) rows.push({ label: esc(T('plan_internal')) + note(T('plan_internal_hint')), f: x => internal.reduce((s, o) => s + orderAmt(o, x), 0), side: 'info' });
                }
                if (!code || code === 'treasury') {
                    for (const name of salaryNames) {
                        rows.push({ label: esc(T('plan_salary', { name })) + note(T('plan_salary_hint')),
                            f: x => Number(((x.salary && x.salary.groups) || {})[name]) || 0, side: 'out' });
                    }
                }
                if (anyRail) {
                    const label = esc(T('plan_rail')) + note(railNote);
                    if (code) {
                        if (railPayer === code) rows.push({ label, f: railTotal, side: 'out' });
                        if (railReceiver === code) rows.push({ label, f: railTotal, side: 'in' });
                    } else if (railPayer && railReceiver) rows.push({ label: esc(T('plan_rail')) + note(railNote + ' · ' + T('plan_rail_internal')), f: railTotal, side: 'info' });
                    else if (railPayer) rows.push({ label, f: railTotal, side: 'out' });
                    else if (railReceiver) rows.push({ label, f: railTotal, side: 'in' });
                    else rows.push({ label: esc(T('plan_rail')) + note(railNote + (rail0 && rail0.booked ? ' · ' + T('plan_rail_not_state') : '')), f: railTotal, side: 'info' });
                }
                return rows;
            }

            function planTable(rows) {
                const inc = x => rows.filter(r => r.side === 'in').reduce((s, r) => s + r.f(x), 0);
                const exp = x => rows.filter(r => r.side === 'out').reduce((s, r) => s + r.f(x), 0);
                const line = r => `<tr${r.side === 'info' ? ' class="dim"' : ''}><td>${r.label}</td>${cells(r.f,
                    r.side === 'in' ? '+' : r.side === 'out' ? '-' : '', r.side === 'in' ? 'pos' : r.side === 'out' ? 'neg' : '')}</tr>`;
                const ins = rows.filter(r => r.side === 'in'), outs = rows.filter(r => r.side === 'out'), infos = rows.filter(r => r.side === 'info');
                const week = days.reduce((s, x) => s + inc(x) - exp(x), 0);
                return table(colHead, [
                    ...(ins.length ? [sec(T('plan_income')), ...ins.map(line)] : []),
                    ...(outs.length ? [sec(T('plan_expense')), ...outs.map(line)] : []),
                    ...infos.map(line),
                    sec(T('plan_net')),
                    `<tr><td>${esc(T('plan_income'))}</td>${cells(inc, '+', 'pos')}</tr>`,
                    `<tr><td>${esc(T('plan_expense'))}</td>${cells(exp, '-', 'neg')}</tr>`,
                    `<tr><td><b>${esc(T('plan_net'))}</b></td>${days.map(x => { const n = inc(x) - exp(x); return `<td class="r mono ${cls(n)}"><b>${signed(n)}</b></td>`; }).join('')}` +
                        `<td class="r mono"><b class="${cls(week)}">${signed(week)}</b></td></tr>`,
                ]);
            }

            let h = head(GOV.title('budgetPlan'), esc(T('plan_hint')));
            h += `<div class="gv-card"><h2>${esc(T('plan_whole'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('plan_whole_hint'))}</div>${planTable(planRows(null))}</div>`;
            for (const a of accounts) {
                const rows = planRows(a.code);
                h += `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(a.name)}</h2><div class="gv-sub mono">${esc(a.code)}</div></div></div>` +
                    (rows.length ? planTable(rows) : `<div class="gv-empty">${esc(T('plan_empty_account'))}</div>`) + '</div>';
            }

            // railway detail: trips per category, stops, run + stop fees per day
            if (anyRail) {
                const cats = [...new Set(days.flatMap(x => Object.keys((x.rail && x.rail.categories) || {})))].sort();
                const num = f => days.map(x => `<td class="r mono">${x.rail ? f(x.rail) : '-'}</td>`).join('') +
                    `<td class="r mono"><b>${days.reduce((s, x) => s + (x.rail ? f(x.rail) : 0), 0)}</b></td>`;
                const cash = f => days.map(x => `<td class="r mono">${x.rail ? money(f(x.rail)) : '-'}</td>`).join('') +
                    `<td class="r mono"><b>${money(days.reduce((s, x) => s + (x.rail ? f(x.rail) : 0), 0))}</b></td>`;
                h += `<div class="gv-card"><h2>${esc(T('plan_rail_detail'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('plan_rail_hint'))} ${esc(railNote)}</div>` +
                    table(colHead, [
                        ...cats.map(c => `<tr><td>${esc(T('plan_rail_trips', { cat: c }))}</td>${num(r => (r.categories[c] || {}).trips || 0)}</tr>`),
                        `<tr><td>${esc(T('plan_rail_stops'))}</td>${num(r => r.stops || 0)}</tr>`,
                        `<tr><td>${esc(T('plan_rail_run'))}</td>${cash(r => r.run || 0)}</tr>`,
                        `<tr><td>${esc(T('plan_rail_stop'))}</td>${cash(r => r.stop || 0)}</tr>`,
                        `<tr><td><b>${esc(T('plan_rail_total'))}</b></td>${cash(r => r.total || 0)}</tr>`,
                    ]) + '</div>';
            }

            // plan items: form (minister) + list
            if (sel.planEdit && !items.some(i => i.id === sel.planEdit)) sel.planEdit = null;
            h += `<div class="gv-card"><h2>${esc(T('plan_items'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('plan_items_hint'))}</div>`;
            if (m) {
                const inp = (id, ph, c) => `<input class="osa-input ${c || 'num'}" id="${id}" placeholder="${esc(ph)}" data-keep="1">`;
                h += `<div class="gv-row">${select('planAccount', accounts.map(a => [a.code, a.name]), sel.planAccount || 'treasury', 'planAccount', true)}` +
                    inp('planName', T('plan_item_name'), 'mid') +
                    select('planKind', [['expense', T('plan_kind_expense')], ['income', T('plan_kind_income')]], sel.planKind || 'expense', 'planKind', true) +
                    `<input class="osa-input mid" id="planNote" placeholder="${esc(T('note'))}" maxlength="64" data-keep="1">` +
                    (sel.planEdit ? `<b>${esc(T('plan_editing', { id: sel.planEdit }))}</b>` : '') + '</div>' +
                    `<div class="gv-row">${[1, 2, 3, 4, 5, 6, 7].map(k => `<label class="dim">${esc(T('day_' + k))}</label>${inp('planD' + k, '0')}`).join('')}</div>` +
                    `<div class="gv-row">${inp('planFill', '€')}${btn(T('plan_fill'), 'planFill')}` +
                    (sel.planEdit ? btn(T('plan_save'), 'planSave', {}, 'primary') + btn(T('plan_cancel'), 'planCancel') : btn(T('plan_add'), 'planSave', {}, 'primary')) + '</div>';
            }
            h += items.length ? table([[T('plan_account')], [T('plan_item_name')], [T('plan_kind')], ...[1, 2, 3, 4, 5, 6, 7].map(k => [T('day_' + k), 'r']), [T('note')], ['', 'act']],
                items.map(i => `<tr${i.id === sel.planEdit ? ' style="outline:1px solid currentColor"' : ''}><td>${esc(accName(itemAcc(i)))}</td><td>${esc(i.name)}</td>` +
                    `<td class="${i.kind === 'income' ? 'pos' : 'neg'}">${esc(T('plan_kind_' + i.kind))}</td>` +
                    [0, 1, 2, 3, 4, 5, 6].map(k => `<td class="r mono">${money(arr(i.amounts)[k] || 0)}</td>`).join('') +
                    `<td class="dim">${esc(i.note || '')}</td><td class="act">${m ? btn(T('plan_edit'), 'planEdit', { id: i.id }) + ' ' +
                        btn(T('delete'), 'planDelete', { id: i.id }, 'danger') : ''}</td></tr>`))
                : `<div class="gv-empty">${esc(T('plan_none'))}</div>`;
            return h + '</div>';
        },
        actions: {
            planKind: el => { sel.planKind = el.value; },
            planAccount: el => { sel.planAccount = el.value; },
            planFill() {
                const v = val('planFill');
                for (let k = 1; k <= 7; k++) if ($('planD' + k)) $('planD' + k).value = v;
            },
            async planSave() {
                const amounts = [];
                for (let k = 1; k <= 7; k++) {
                    const s = val('planD' + k);
                    const n = s === '' ? 0 : GOV.ui.num(s);
                    if (n === null || n < 0) return OSA.toast(T('gov_core.err.bad_number'), false);
                    amounts.push(Math.round(n));
                }
                const args = { account: val('planAccount') || 'treasury', name: val('planName'), kind: val('planKind') || 'expense', amounts, note: val('planNote') };
                if (sel.planEdit) args.id = sel.planEdit;
                if (await GOV.change('savePlanItem', args)) {
                    sel.planEdit = null;
                    for (const id of ['planName', 'planNote', 'planFill', 'planD1', 'planD2', 'planD3', 'planD4', 'planD5', 'planD6', 'planD7']) if ($(id)) $(id).value = '';
                    GOV.render();
                }
            },
            planEdit(b) {
                const it = arr((D.budgetPlan || {}).items).find(x => x.id === Number(b.dataset.id));
                if (!it) return;
                sel.planEdit = it.id;
                sel.planKind = it.kind;
                sel.planAccount = it.account || 'treasury';
                GOV.render();
                const set = (id, v) => { const el = $(id); if (el) el.value = v; };
                set('planName', it.name);
                set('planNote', it.note || '');
                for (let k = 1; k <= 7; k++) set('planD' + k, arr(it.amounts)[k - 1] || 0);
                $('planName') && $('planName').scrollIntoView({ block: 'center' });
            },
            planCancel() {
                sel.planEdit = null;
                for (const id of ['planName', 'planNote', 'planFill', 'planD1', 'planD2', 'planD3', 'planD4', 'planD5', 'planD6', 'planD7']) if ($(id)) $(id).value = '';
                GOV.render();
            },
            async planDelete(b) {
                if (await OSA.ui.confirm(GOV.title('budgetPlan'), T('confirm_delete_plan'), T('delete'))) GOV.change('deletePlanItem', { id: Number(b.dataset.id) });
            },
        },
    });
})();
