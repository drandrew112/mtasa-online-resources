// gov_railways - the Railways page of /gov (see gov_core web/js/gov.js GOV.page).
// Operator (the company whose members edit the timetable; minister), the fixed routes, the
// timetable rows of rw_timetable (form + table) and the departures of a day as the trains run.
// Times are minutes after midnight on the server, HH:MM on the page.
(function () {
    'use strict';
    const { esc, arr, $, val, money, head, table, btn, select, payerName } = GOV.ui;
    const T = GOV.tr('gov_railways');
    const sel = GOV.sel;
    const SECTOR = 'railways';
    const DAY_PRESETS = [[127, 'days_all'], [31, 'days_work'], [96, 'days_weekend']];

    const hm = m => { m = ((Number(m) || 0) % 1440 + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
    // "6:05", "06:05", "0605", "6" -> minutes after midnight, or null
    const parseHm = s => {
        s = String(s || '').trim();
        let h, m;
        let x = s.match(/^(\d{1,2})[:.](\d{2})$/);
        if (x) { h = +x[1]; m = +x[2]; }
        else if ((x = s.match(/^(\d{1,2})$/))) { h = +x[1]; m = 0; }
        else if ((x = s.match(/^(\d{2})(\d{2})$/))) { h = +x[1]; m = +x[2]; }
        else return null;
        return h < 24 && m < 60 ? h * 60 + m : null;
    };
    const short = n => String(n || '').replace(/ Station$/, '');

    GOV.page('railways', {
        keys: [...GOV.keys('gov_railways', ['operator', 'operator_hint', 'op_none', 'search_operator', 'routes', 'routes_hint',
            'line', 'stops', 'starts_at', 'rules', 'rules_hint', 'kind', 'kind_interval', 'kind_single', 'from', 'to',
            'first', 'last', 'every', 'min', 'dep_at', 'days', 'date', 'date_hint', 'number', 'number_hint', 'add_rule', 'save_rule',
            'cancel', 'editing', 'edit', 'pause', 'resume', 'paused', 'trains', 'single', 'only_on', 'confirm_delete_rule',
            'departures', 'departures_hint', 'today', 'tomorrow', 'no_trains', 'tt_offline', 'not_loaded', 'stretch', 'extra',
            'days_all', 'days_work', 'days_weekend', 'total_trains', 'updated',
            'day_1', 'day_2', 'day_3', 'day_4', 'day_5', 'day_6', 'day_7', 'costs', 'costs_hint', 'cost_flow', 'cost_not_booked',
            'cost_run', 'cost_stops', 'cost_total', 'week', 'nobody']), 'gov_railways.err.bad_time', 'gov_railways.err.bad_last'],
        load: () => GOV.call('railways', { day: sel.railDay || 0 }),
        render(d) {
            // gov_perms (or the operator company: gov_core sector rights)
            const edit = GOV.can('rail.timetable.edit');
            const toggle = GOV.can('rail.timetable.toggle');
            const minister = GOV.can('rail.operator.set');
            let h = head(GOV.title('railways'));

            // ---------------------------------------------------- operator
            const opState = () => [{ spec: 'none', name: T('op_none') },
                ...arr(d.payers).filter(x => x.spec !== 'system' && x.spec !== 'state:treasury')];
            const opName = spec => spec === 'none' || !spec ? { name: T('op_none'), tag: '' } : payerName(d, spec);
            if (minister) GOV.usePicker('railOp', {
                state: opState,
                current: () => d.operator,
                choose: it => GOV.change('setRailOperator', { spec: it.spec }),
            });
            h += `<div class="gv-card"><h2>${esc(T('operator'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('operator_hint'))}</div>` +
                `<div class="gv-field"><label>${esc(T('operator'))}</label>${GOV.pickerBox('railOp', opName(d.operator), minister, T('search_operator'))}</div></div>`;

            if (!d.online) return h + `<div class="gv-card"><div class="gv-empty">${esc(T('tt_offline'))}</div></div>`;
            if (!d.loaded) h += `<div class="gv-card"><div class="gv-sub">${esc(T('not_loaded'))}</div></div>`;

            const lines = arr(d.lines);
            const lineOf = id => lines.find(l => l.id === id);
            const stName = id => { const s = arr(d.stations).find(x => x.id === id); return short(s ? s.name : id); };
            const lineTag = l => `<b>${esc(l.id)}</b> <span class="dim">${esc(l.prefix)}</span>`;
            const route = l => arr(l.stops).map(s => stName(s.station)).join(' – ');
            // the stations a trip may end at when it starts at `from` (stops after it with an arrival)
            const endsOf = (l, from) => {
                const st = arr(l.stops), i = st.findIndex(s => s.station === from && s.dep !== false);
                const out = [];
                if (i < 0) return out;
                for (let j = i + 1; j < st.length; j++) if (st[j].arr !== false && !out.includes(st[j].station)) out.push(st[j].station);
                return out;
            };

            // ---------------------------------------------------- routes (fixed)
            h += `<div class="gv-card"><h2>${esc(T('routes'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('routes_hint'))}</div>` +
                table([[T('line')], [''], [T('stops')], [T('starts_at')]], lines.map(l =>
                    `<tr><td>${lineTag(l)}</td><td>${esc(l.name)}</td><td>${arr(l.stops).map(s =>
                        `${esc(stName(s.station))} <span class="dim mono">${s.arr !== false ? s.arr + '′' : ''}${s.arr !== false && s.dep !== false ? '/' : ''}${s.dep !== false ? s.dep + '′' : ''}</span>`).join(' – ')}</td>` +
                    `<td>${esc(arr(l.origins).map(stName).join(', '))}</td></tr>`)) + '</div>';

            // ---------------------------------------------------- timetable rows
            const rows = arr(d.rows).slice().sort((a, b) => a.line === b.line ? a.first - b.first : (a.line < b.line ? -1 : 1));
            if (sel.rfEdit && !rows.some(r => r.id === sel.rfEdit)) sel.rfEdit = null;   // deleted meanwhile
            h += `<div class="gv-card"><h2>${esc(T('rules'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('rules_hint'))}</div>`;
            if (edit && lines.length) {
                const f = sel.rf || (sel.rf = { line: lines[0].id, kind: 'interval', days: 127 });
                const l = lineOf(f.line) || lines[0];
                f.line = l.id;
                if (!arr(l.origins).includes(f.from)) f.from = arr(l.origins)[0];
                const ends = endsOf(l, f.from);
                if (!ends.includes(f.to)) f.to = ends.includes(l.to) ? l.to : ends[ends.length - 1];
                const inp = (id, ph, cls) => `<input class="osa-input ${cls || 'num'}" id="${id}" placeholder="${esc(ph)}" data-keep="1">`;
                const dayBtns = [1, 2, 3, 4, 5, 6, 7].map(k => {
                    const on = (f.days >> (k - 1)) & 1;
                    return `<button class="osa-btn small ${on ? 'primary' : ''}" data-act="rfDay" data-bit="${k - 1}">${esc(T('day_' + k))}</button>`;
                }).join('') + DAY_PRESETS.map(([v, k]) => btn(T(k), 'rfDays', { value: v })).join('');
                h += `<div class="gv-row">${select('rfLine', lines.map(x => [x.id, `${x.id} ${x.prefix} · ${route(x)}`]), f.line, 'rfLine', true)}` +
                    select('rfKind', [['interval', T('kind_interval')], ['single', T('kind_single')]], f.kind, 'rfKind', true) +
                    (sel.rfEdit ? `<b>${esc(T('editing', { id: sel.rfEdit }))}</b>` : '') + '</div>' +
                    `<div class="gv-row"><label class="dim">${esc(T('from'))}</label>${select('rfFrom', arr(l.origins).map(s => [s, stName(s)]), f.from, 'rfFrom', true)}` +
                    `<label class="dim">${esc(T('to'))}</label>${select('rfTo', ends.map(s => [s, stName(s)]), f.to, 'rfTo', true)}</div>` +
                    (f.kind === 'interval'
                        ? `<div class="gv-row"><label class="dim">${esc(T('first'))}</label>${inp('rfFirst', '06:00')}<label class="dim">${esc(T('last'))}</label>${inp('rfLast', '21:00')}` +
                          `<label class="dim">${esc(T('every'))}</label>${inp('rfEvery', '15')}<span class="gv-unit">${esc(T('min'))}</span></div>`
                        : `<div class="gv-row"><label class="dim">${esc(T('dep_at'))}</label>${inp('rfFirst', '07:42')}` +
                          `<label class="dim">${esc(T('number'))}</label>${inp('rfNumber', T('number_hint'))}</div>`) +
                    `<div class="gv-row"><label class="dim">${esc(T('days'))}</label>${dayBtns}</div>` +
                    `<div class="gv-row"><label class="dim">${esc(T('date'))}</label>${inp('rfDate', T('date_hint'), 'mid')}` +
                    `<input class="osa-input mid" id="rfNote" placeholder="${esc(T('note'))}" maxlength="128" data-keep="1">` +
                    (sel.rfEdit ? btn(T('save_rule'), 'rfSave', {}, 'primary') + btn(T('cancel'), 'rfCancel') : btn(T('add_rule'), 'rfSave', {}, 'primary')) + '</div>';
            }
            const dayText = r => {
                const p = DAY_PRESETS.find(([v]) => v === r.days);
                let s = p ? T(p[1]) : [1, 2, 3, 4, 5, 6, 7].filter(k => (r.days >> (k - 1)) & 1).map(k => T('day_' + k)).join(' ');
                if (r.date) s += ' · ' + T('only_on', { date: r.date });
                return s;
            };
            const depText = r => r.kind === 'single'
                ? `${hm(r.first)} · ${T('single')}${r.number ? ' · ' + (lineOf(r.line) || {}).prefix + ' ' + r.number : ''}`
                : `${hm(r.first)}–${hm(r.last)} · ${T('every')} ${r.headway} ${T('min')} · ${Math.floor((r.last - r.first) / r.headway) + 1} ${T('trains')}`;
            h += table([[T('line')], [T('stretch')], [T('departures')], [T('days')], [T('note')], [T('updated')], ['', 'act']], rows.map(r => {
                const l = lineOf(r.line);
                return `<tr${r.active ? '' : ' class="dim"'}${r.id === sel.rfEdit ? ' style="outline:1px solid currentColor"' : ''}>` +
                    `<td>${l ? lineTag(l) : esc(r.line)}</td><td>${esc(stName(r.from))} → ${esc(stName(r.to))}</td>` +
                    `<td class="mono">${esc(depText(r))}${r.active ? '' : ` <span class="tag bad">${esc(T('paused'))}</span>`}</td>` +
                    `<td>${esc(dayText(r))}</td><td class="dim">${esc(r.note || '')}</td><td class="dim">${esc(r.updatedBy || '')}</td>` +
                    `<td class="act">${edit ? btn(T('edit'), 'rfEdit', { id: r.id }) + ' ' : ''}` +
                        `${toggle ? btn(T(r.active ? 'pause' : 'resume'), 'rfToggle', { id: r.id, value: r.active ? 'false' : 'true' }) + ' ' : ''}` +
                        `${edit ? btn(T('delete'), 'rfDelete', { id: r.id }, 'danger') : ''}</td></tr>`;
            })) + '</div>';

            // ---------------------------------------------------- running costs of the week
            const costs = arr(d.costs);
            if (costs.length) {
                const c0 = costs[0].cost;
                const who = spec => spec === 'system' ? T('nobody') : payerName(d, spec).name;
                const flow = c0 ? (c0.booked ? T('cost_flow', { payer: who(c0.payer), receiver: who(c0.receiver) }) : T('cost_not_booked')) : '';
                const week = costs.reduce((s, x) => s + (x.cost ? x.cost.total : 0), 0);
                const label = x => x.day === 0 ? T('today') : x.day === 1 ? T('tomorrow') : T('day_' + x.weekday);
                h += `<div class="gv-card"><h2>${esc(T('costs'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('costs_hint'))} ${esc(flow)}</div>` +
                    table([[''], ...costs.map(x => [label(x), 'r']), [T('week'), 'r']], [
                        `<tr><td>${esc(T('trains'))}</td>${costs.map(x => `<td class="r mono">${x.cost ? x.cost.trips : '-'}</td>`).join('')}` +
                            `<td class="r mono">${costs.reduce((s, x) => s + (x.cost ? x.cost.trips : 0), 0)}</td></tr>`,
                        `<tr><td>${esc(T('cost_run'))}</td>${costs.map(x => `<td class="r mono">${x.cost ? money(x.cost.run) : '-'}</td>`).join('')}<td></td></tr>`,
                        `<tr><td>${esc(T('cost_stops'))}</td>${costs.map(x => `<td class="r mono">${x.cost ? money(x.cost.stop) : '-'}</td>`).join('')}<td></td></tr>`,
                        `<tr><td><b>${esc(T('cost_total'))}</b></td>${costs.map(x => `<td class="r mono neg"><b>${x.cost ? money(x.cost.total) : '-'}</b></td>`).join('')}` +
                            `<td class="r mono neg"><b>${money(week)}</b></td></tr>`,
                    ]) + '</div>';
            }

            // ---------------------------------------------------- departures of a day
            const base = (d.dayTs || 0) - (d.day || 0) * 86400;
            const dayLabel = k => k === 0 ? T('today') : k === 1 ? T('tomorrow') : T('day_' + (((new Date((base + k * 86400) * 1000).getDay() + 6) % 7) + 1));
            const deps = arr(d.departures);
            h += `<div class="gv-card"><h2>${esc(T('departures'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('departures_hint'))}</div>` +
                `<div class="gv-row" style="margin-bottom:10px">${[0, 1, 2, 3, 4, 5, 6].map(k =>
                    `<button class="osa-btn small ${k === (d.day || 0) ? 'primary' : ''}" data-act="rfShowDay" data-day="${k}">${esc(dayLabel(k))}</button>`).join('')}` +
                `<span class="dim">${esc(T('total_trains', { n: deps.length }))}</span></div>`;
            if (!deps.length) h += `<div class="gv-empty">${esc(T('no_trains'))}</div>`;
            for (const l of lines) {
                const mine = deps.filter(x => x.line === l.id);
                if (!mine.length) continue;
                h += `<div style="margin:12px 0 4px">${lineTag(l)} <span class="dim">${esc(route(l))} · ${mine.length} ${esc(T('trains'))}</span></div>` +
                    `<div class="mono" style="display:flex;flex-wrap:wrap;gap:4px 12px">${mine.map(x => {
                        const part = x.from !== l.from || x.to !== l.to ? ` <span class="dim">${esc(stName(x.from))}→${esc(stName(x.to))}</span>` : '';
                        return `<span title="${esc(x.number)}"${x.single ? ` style="font-weight:700"` : ''}>${hm(x.dep)}${part}</span>`;
                    }).join('')}</div>`;
            }
            return h + '</div>';
        },
        actions: {
            rfLine: el => { sel.rf.line = el.value; GOV.render(); },
            rfKind: el => { sel.rf.kind = el.value; GOV.render(); },
            rfFrom: el => { sel.rf.from = el.value; GOV.render(); },
            rfTo: el => { sel.rf.to = el.value; },
            rfDay(b) { sel.rf.days ^= 1 << Number(b.dataset.bit); if (!sel.rf.days) sel.rf.days = 127; GOV.render(); },
            rfDays(b) { sel.rf.days = Number(b.dataset.value); GOV.render(); },
            rfShowDay(b) { sel.railDay = Number(b.dataset.day); GOV.load(); },
            async rfSave() {
                const f = sel.rf;
                const first = parseHm(val('rfFirst'));
                if (first === null) return OSA.toast(T('gov_railways.err.bad_time'), false);
                const row = { line: f.line, kind: f.kind, from: f.from, to: val('rfTo') || f.to, first, days: f.days,
                    date: val('rfDate'), note: val('rfNote') };
                if (f.kind === 'interval') {
                    row.last = parseHm(val('rfLast'));
                    row.headway = Number(val('rfEvery'));
                    if (row.last === null) return OSA.toast(T('gov_railways.err.bad_last'), false);
                } else if (val('rfNumber')) row.number = Number(val('rfNumber'));
                const args = { row };
                if (sel.rfEdit) args.id = sel.rfEdit;
                if (await GOV.change('saveRailRow', args)) {
                    sel.rfEdit = null;
                    for (const id of ['rfFirst', 'rfLast', 'rfEvery', 'rfNumber', 'rfDate', 'rfNote']) if ($(id)) $(id).value = '';
                    GOV.render();
                }
            },
            // loads a row into the form; Save then changes it
            rfEdit(b) {
                const r = arr((GOV.D.railways || {}).rows).find(x => x.id === Number(b.dataset.id));
                if (!r) return;
                sel.rfEdit = r.id;
                sel.rf = { line: r.line, kind: r.kind, from: r.from, to: r.to, days: r.days };
                GOV.render();
                const set = (id, v) => { const el = $(id); if (el) el.value = v; };
                set('rfFirst', hm(r.first));
                if (r.kind === 'interval') { set('rfLast', hm(r.last)); set('rfEvery', r.headway); }
                else set('rfNumber', r.number || '');
                set('rfDate', r.date || '');
                set('rfNote', r.note || '');
                $('rfLine') && $('rfLine').scrollIntoView({ block: 'center' });
            },
            rfCancel() {
                sel.rfEdit = null;
                for (const id of ['rfFirst', 'rfLast', 'rfEvery', 'rfNumber', 'rfDate', 'rfNote']) if ($(id)) $(id).value = '';
                GOV.render();
            },
            rfToggle(b) { GOV.change('toggleRailRow', { id: Number(b.dataset.id), active: b.dataset.value === 'true' }); },
            async rfDelete(b) {
                if (await OSA.ui.confirm(T('rules'), T('confirm_delete_rule'), T('delete'))) GOV.change('deleteRailRow', { id: Number(b.dataset.id) });
            },
        },
    });
})();
