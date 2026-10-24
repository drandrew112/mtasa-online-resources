// v_gov - the /gov panel. One page with a side menu; every request goes through client/panel.lua
// to server/panel.lua (the same actions and role checks as before):
//   GOV.call(action, args) -> Promise<result>   (rejects with the translated error text)
// Texts come from v_locals: KEYS is sent to the client on start, GOV._init returns them.
(function () {
    'use strict';
    const esc = OSA.esc;
    const arr = OSA.arr;
    const $ = id => document.getElementById(id);
    const view = $('view');

    const PAGES = ['overview', 'treasury', 'transfers', 'budget', 'taxes', 'works', 'fees', 'health', 'companies', 'votes', 'news', 'members', 'log'];
    const VAT_GROUPS = ['weapons', 'clothing', 'vehicles', 'tuning', 'repair', 'services', 'real_estate'];
    const GROUPS = ['all', 'tax', 'fine', 'health', 'work', 'biz', 'gov', 'atc', 'transfer', 'admin'];
    const ROLE_LEVEL = { viewer: 1, official: 2, minister: 3 };
    const ACC_ROLES = ['manager', 'viewer', 'owner'];
    const FEE_KEYS = ['register', 'rename', 'bay_fine', 'airspace.takeoff', 'airspace.landing', 'airspace.overflight'];

    const KEYS = [
        ...['title', 'loading', 'empty', 'saved', 'treasury_balance', 'last_24h', 'last_7d', 'tax_runs', 'companies_n',
            'older', 'amount', 'note', 'from_treasury', 'to_treasury', 'company_tax', 'income_keys', 'add_key', 'key_name',
            'delete', 'reset', 'payer', 'private_company', 'company_name', 'multiplier', 'tax_key', 'params', 'default_n',
            'health_enabled', 'on', 'off', 'hp_price', 'injury_prices', 'add_injury', 'injury_type', 'create_company',
            'company_code', 'pays_works', 'rename', 'overdraft_on', 'overdraft_off', 'delete_company', 'add_member', 'role',
            'account_name', 'members', 'remove', 'admins_are_ministers', 'save', 'close', 'search_company',
            'state_payers', 'private_companies', 'no_match', 'searching', 'state_accounts', 'income', 'expense',
            'group', 'time', 'description', 'balance', 'period', 'total', 'actor', 'action', 'detail', 'filter',
            'current_payer', 'inactive', 'confirm_close_company', 'confirm_delete', 'severity_n', 'value', 'default',
            'account', 'search_work', 'overdraft', 'create', 'companies', 'vat', 'vat_hint', 'property_tax',
            'property_tax_hint', 'history_note', 'net', 'company_description', 'votes_open', 'votes_closed', 'new_vote',
            'vote_title', 'vote_description', 'vote_options', 'vote_options_hint', 'vote_hours', 'vote_ends', 'voters_n',
            'close_vote', 'cancel_vote', 'status_open', 'status_closed', 'status_cancelled', 'results_after_close',
            'winner', 'created', 'daily', 'day', 'new_news', 'news_title', 'news_body', 'news_send', 'news_hint',
            'news_not_mailed', 'confirm_delete_news', 'tax_target', 'tax_target_none', 'tax_target_missing',
            'hospitals', 'receiver', 'patient_pays', 'receiver_none', 'payer_system', 'search_payer', 'search_private',
            'default_payer', 'hospital_missing', 'hospitals_offline', 'no_heal_marker', 'patient_pays_hint',
            'tf_state', 'tf_pay', 'tf_collect', 'tf_collect_hint', 'tf_from', 'tf_to', 'tf_send', 'tf_pay_btn',
            'tf_collect_btn', 'tf_recent', 'tf_kind', 'tf_pick_company', 'confirm_transfer']
            .map(k => 'v_gov.ui.' + k),
        ...PAGES.map(p => 'v_gov.page.' + p),
        ...['viewer', 'official', 'minister'].map(r => 'v_gov.role.' + r),
        ...FEE_KEYS.map(k => 'v_gov.fee.' + k),
        ...GROUPS.map(g => 'v_bank.group.' + g),
        ...['shop', 'cash', 'other'].map(g => 'v_bank.group.' + g),
        ...VAT_GROUPS.map(g => 'v_gov.vat.' + g),
        'v_gov.err.bad_number',
    ];
    let STR = {};
    const T = (key, params) => {
        const full = key.includes('.') ? key : 'v_gov.ui.' + key;
        let s = STR[full];
        if (s === undefined) s = full.split('.').pop().replace(/_/g, ' ');
        return params ? String(s).replace(/\{(\w+)\}/g, (m, k) => params[k] ?? m) : String(s);
    };

    const money = n => (n < 0 ? '−€' : '€') + Math.abs(Math.round(Number(n) || 0)).toLocaleString('en-US');
    const signed = n => (n > 0 ? '+' : '') + money(n);
    const cls = n => (n < 0 ? 'neg' : 'pos');
    const pct = r => (Math.round((Number(r) || 0) * 1000) / 10) + '%';
    const stamp = ts => {
        const d = new Date(ts * 1000);
        return d.toLocaleDateString('en-GB', { month: '2-digit', day: '2-digit' }) + ' ' +
            d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    };
    const num = v => {
        const n = Number(String(v).replace(/\s/g, '').replace(',', '.'));
        return String(v).trim() !== '' && isFinite(n) ? n : null;
    };

    // ------------------------------------------------------------ bridge (client/panel.lua)
    const GOV = window.GOV = {};
    const waiting = {};
    let nextId = 0;
    const inGame = !!(window.mta && mta.triggerEvent);

    GOV.call = (action, args) => new Promise((resolve, reject) => {
        if (!inGame) return reject(new Error('Only in game.'));
        const id = ++nextId;
        waiting[id] = { resolve, reject };
        mta.triggerEvent('v_gov:pageCall', id, action, JSON.stringify([args || {}]));
    });
    GOV._resolve = (id, result, error) => {
        const w = waiting[id];
        delete waiting[id];
        if (!w) return;
        if (result === false) w.reject(new Error(error || 'Error'));
        else w.resolve(result);
    };

    let role = 'viewer';
    const can = need => (ROLE_LEVEL[role] || 0) >= ROLE_LEVEL[need];

    GOV._init = data => {
        role = data.role || 'viewer';
        STR = data.strings || {};
        $('title').textContent = T('title');
        $('role').textContent = T('v_gov.role.' + role);
        $('closeBtn').textContent = T('close') + ' (Esc)';
        document.title = T('title');
        nav();
        show(page);
    };

    function close() { if (inGame) mta.triggerEvent('v_gov:pageClose'); }
    // Esc reaches both the page (osa.js closes its dialog) and client/panel.lua (-> _escape), in
    // either order: the panel closes only when no dialog / list was open at that key press
    let escOverlayAt = 0;
    const overlayOpen = () => !!document.querySelector('.osa-modal-back:not([hidden])') || anyPickerOpen();
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        if (overlayOpen()) escOverlayAt = Date.now();
        hidePickers();
    }, true);
    GOV._escape = () => {
        if (document.querySelector('.osa-modal-back:not([hidden])')) { OSA.ui.closeModal(); return; }
        if (anyPickerOpen()) { hidePickers(); return; }
        if (Date.now() - escOverlayAt < 500) return;
        close();
    };
    $('closeBtn').addEventListener('click', close);

    // ------------------------------------------------------------ state + navigation
    let page = 'overview';
    const D = {};             // data per page
    const sel = { treasury: null, group: 'all', work: null, company: null, workQ: '', logQ: '', newsDraft: null,
        hospital: null, tfPay: null, tfCol: null };
    let busy = false;

    function nav() {
        $('nav').innerHTML = PAGES.map(p => `<a data-page="${p}" class="${p === page ? 'on' : ''}">${esc(T('v_gov.page.' + p))}</a>`).join('');
    }
    $('nav').addEventListener('click', e => {
        const a = e.target.closest('a[data-page]');
        if (a) show(a.dataset.page);
    });

    function show(p) {
        page = p;
        hidePickers();
        nav();
        if (!D[p]) view.innerHTML = `<h1>${esc(T('v_gov.page.' + p))}</h1><div class="gv-empty">${esc(T('loading'))}</div>`;
        else render();
        load(p);
    }

    async function load(p) {
        try {
            if (p === 'treasury') {
                if (!D.overview) D.overview = await GOV.call('overview');
                D.treasury = await GOV.call('treasuryLedger', { id: sel.treasury || undefined, group: sel.group !== 'all' ? sel.group : undefined });
                sel.treasury = D.treasury.id;
            } else if (p === 'companies') {
                D.companies = await GOV.call('companies');
                if (sel.company) D.company = (await GOV.call('company', { id: sel.company })).company;
            } else {
                D[p] = await GOV.call(p);
            }
        } catch (e) {
            OSA.toast(e.message, false);
        }
        if (page === p) render();
    }

    // a change, then the page again
    async function change(action, args) {
        if (busy) return false;
        busy = true;
        let ok = true;
        try {
            await GOV.call(action, args);
            OSA.toast(T('saved'), true);
        } catch (e) {
            ok = false;
            OSA.toast(e.message, false);
        }
        busy = false;
        await load(page);
        return ok;
    }

    // keeps typed values, focus and scroll across a re-render
    function render() {
        const vals = {};
        for (const el of view.querySelectorAll('input[id], select[id]')) if (el.classList.contains('dirty') || el.dataset.keep) vals[el.id] = el.value;
        const focus = document.activeElement && document.activeElement.id;
        const scroll = view.scrollTop;
        view.innerHTML = PAGE[page](D[page] || {});
        for (const id in vals) { const el = $(id); if (el) { el.value = vals[id]; mark(el); } }
        const f = focus && $(focus);
        if (f) {
            f.focus();
            if (f.tagName === 'INPUT') f.setSelectionRange(f.value.length, f.value.length);
        }
        view.scrollTop = scroll;
        mountPickers();
    }

    // ------------------------------------------------------------ building blocks
    const head = (title, sub, right) => `<div class="gv-head"><div><h1>${esc(title)}</h1>${sub ? `<div class="gv-sub">${sub}</div>` : ''}</div>${right || ''}</div>`;
    const kpi = (k, v, c) => `<div class="gv-kpi"><div class="k">${esc(k)}</div><div class="v ${c || ''}">${v}</div></div>`;
    const empty = () => `<div class="gv-empty">${esc(T('empty'))}</div>`;
    const table = (cols, rows) => rows.length ? `<table class="gv-table"><thead><tr>${cols.map(c =>
        `<th class="${c[1] || ''}">${esc(c[0])}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table>` : empty();
    const btn = (label, act, data, style, disabled) =>
        `<button class="osa-btn small ${style || ''}" data-act="${act}" ${Object.entries(data || {}).map(([k, v]) =>
            `data-${k}="${esc(v)}"`).join(' ')}${disabled ? ' disabled' : ''}>${esc(label)}</button>`;
    // a value input + Save (+ Default): the input remembers the stored value to show "changed"
    const edit = (id, value, act, data, opts) => {
        opts = opts || {};
        if (!opts.allowed) return `<span class="mono">${esc(opts.shown ?? value)}</span>`;
        return `<span class="gv-row" style="display:inline-flex"><input class="osa-input ${opts.cls || 'num'}" id="${id}" value="${esc(value)}" data-orig="${esc(value)}" data-enter="${act}">` +
            (opts.unit ? `<span class="gv-unit">${esc(opts.unit)}</span>` : '') +
            btn(T('save'), act, Object.assign({ input: id }, data), 'primary') +
            (opts.reset ? btn(T('reset'), opts.reset, data) : '') + '</span>';
    };
    const toggle = (on, act, data, allowed, labels) =>
        `<span class="gv-toggle">${[true, false].map(v => `<button data-act="${act}" data-value="${v}" ${Object.entries(data || {}).map(([k, x]) =>
            `data-${k}="${esc(x)}"`).join(' ')} class="${on === v ? 'on' : ''}"${allowed ? '' : ' disabled'}>${esc(labels[v ? 0 : 1])}</button>`).join('')}</span>`;
    const select = (id, options, value, act, allowed) =>
        `<select class="osa-select" id="${id}" data-change="${act}"${allowed ? '' : ' disabled'}>${options.map(([v, l]) =>
            `<option value="${esc(v)}"${String(v) === String(value) ? ' selected' : ''}>${esc(l)}</option>`).join('')}</select>`;

    function mark(el) {
        if (el.dataset.orig !== undefined) el.classList.toggle('dirty', el.value !== el.dataset.orig);
    }
    view.addEventListener('input', e => mark(e.target));

    // ------------------------------------------------------------ pages
    const PAGE = {};

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
    const runsTable = runs => table([[T('period')], [T('companies'), 'r'], [T('total'), 'r']],
        arr(runs).map(r => `<tr><td class="mono">${stamp(r.period)}</td><td class="r">${r.companies}</td><td class="r mono pos">${money(r.total)}</td></tr>`));

    PAGE.overview = d => {
        const t = d.treasury || {};
        const groups = (stats) => table([[T('group')], [T('income'), 'r'], [T('expense'), 'r']], groupSums(stats).map(([n, s]) =>
            `<tr><td>${esc(T('v_bank.group.' + n))}</td><td class="r mono pos">+${money(s.inSum)}</td><td class="r mono neg">-${money(s.outSum)}</td></tr>`));
        return head(T('v_gov.page.overview')) +
            `<div class="gv-kpis">${kpi(T('treasury_balance'), money(t.balance), cls(t.balance))}` +
            kpi(T('last_24h'), signed(sumOf(d.day, 'inSum') - sumOf(d.day, 'outSum')), cls(sumOf(d.day, 'inSum') - sumOf(d.day, 'outSum'))) +
            kpi(T('last_7d'), signed(sumOf(d.week, 'inSum') - sumOf(d.week, 'outSum')), cls(sumOf(d.week, 'inSum') - sumOf(d.week, 'outSum'))) + '</div>' +
            `<div class="gv-grid2"><div class="gv-card"><h2>${esc(T('last_24h'))}</h2>${groups(d.day)}</div>` +
            `<div class="gv-card"><h2>${esc(T('last_7d'))}</h2>${groups(d.week)}</div></div>` +
            `<div class="gv-grid2"><div class="gv-card"><h2>${esc(T('state_accounts'))}</h2>` +
            table([[T('account')], [T('balance'), 'r']], arr(d.states).filter(s => s.status !== 'closed').map(s =>
                `<tr><td>${esc(s.name)} <span class="dim mono">${esc(s.number || '')}</span></td><td class="r mono ${cls(s.balance)}">${money(s.balance)}</td></tr>`)) +
            `</div><div class="gv-card"><h2>${esc(T('tax_runs'))}</h2>${runsTable(d.runs)}</div></div>`;
    };

    PAGE.treasury = d => {
        const states = arr(D.overview && D.overview.states).filter(s => s.status !== 'closed');
        const cur = states.find(s => s.id === d.id);
        let h = head(T('v_gov.page.treasury'), esc(T('history_note', { days: 30 })), cur ? `<div class="big ${cls(cur.balance)}">${money(cur.balance)}</div>` : '') +
            `<div class="gv-row">${select('trAcc', states.map(s => [s.id, s.name]), d.id, 'trAcc', true)}` +
            select('trGroup', GROUPS.map(g => [g, T('v_bank.group.' + g)]), sel.group, 'trGroup', true) + '</div>';
        if (can('minister') && cur && cur.ownerRef !== 'treasury') {
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
    };

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

    PAGE.taxes = d => {
        const m = can('minister');
        const keys = Object.entries(d.keys || {}).sort((a, b) => a[0].localeCompare(b[0]));
        let h = head(T('v_gov.page.taxes')) +
            `<div class="gv-card"><div class="gv-field"><label>${esc(T('company_tax'))}</label><div>` +
            edit('companyTax', Math.round((d.company || 0) * 1000) / 10, 'companyTax', {}, { allowed: m, unit: '%', shown: pct(d.company) }) + '</div></div>' +
            taxTarget(d, 'company', m) + '</div>' +
            `<div class="gv-card"><h2>${esc(T('income_keys'))}</h2>` + taxTarget(d, 'income', m) +
            table([[T('tax_key')], [T('v_gov.page.works')], [T('value'), 'r'], ['', 'act']], keys.map(([k, r]) =>
                `<tr><td><b>${esc(k)}</b></td><td class="dim">${esc(arr(d.used && d.used[k]).join(', ') || '-')}</td>` +
                `<td class="r">${edit('key_' + k, Math.round(r * 1000) / 10, 'taxKey', { key: k }, { allowed: m, unit: '%', shown: pct(r) })}</td>` +
                `<td class="act">${m && k !== 'standard' ? btn(T('delete'), 'deleteTaxKey', { key: k }, 'danger') : ''}</td></tr>`));
        if (m) {
            h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="newKey" placeholder="${esc(T('key_name'))}" maxlength="24" data-keep="1">` +
                `<input class="osa-input num" id="newKeyRate" placeholder="%" data-keep="1" data-enter="addTaxKey">${btn(T('add_key'), 'addTaxKey', {}, 'primary')}</div>`;
        }
        h += `</div><div class="gv-card"><h2>${esc(T('vat'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('vat_hint'))}</div>` + taxTarget(d, 'vat', m) +
            table([[T('group')], [T('default'), 'r'], [T('value'), 'r']], arr(d.vat).map(v =>
                `<tr><td>${esc(T('v_gov.vat.' + v.group))}</td><td class="r mono dim">${pct(v.default)}</td>` +
                `<td class="r">${edit('vat_' + v.group, Math.round(v.rate * 1000) / 10, 'vat', { group: v.group },
                    { allowed: m, unit: '%', reset: 'vatReset', shown: pct(v.rate) })}</td></tr>`)) + '</div>' +
            `<div class="gv-card"><div class="gv-field"><label>${esc(T('property_tax'))}</label><div>` +
            edit('propTax', Math.round((d.property || 0) * 10000) / 100, 'propTax', {}, { allowed: m, unit: '%', reset: 'propTaxReset',
                shown: (Math.round((d.property || 0) * 10000) / 100) + '%' }) +
            `<div class="gv-sub">${esc(T('property_tax_hint'))}</div></div></div>` + taxTarget(d, 'property', m) + '</div>';
        return h + `<div class="gv-card"><h2>${esc(T('tax_runs'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('history_note', { days: 30 }))}</div>${runsTable(d.runs)}</div>`;
    };

    function payerName(d, spec) {
        const p = arr(d.payers).find(x => x.spec === spec);
        if (p) return { name: p.name, tag: spec === 'system' ? '' : 'state' };
        const id = (spec.match(/^company:(\d+)$/) || [])[1];
        if (id) {
            const c = d.companies && d.companies[id];
            return { name: c ? c.name : T('private_company', { id }), tag: 'company', inactive: c && !c.active, id };
        }
        return { name: spec, tag: '' };
    }

    PAGE.works = d => {
        const m = can('minister');
        const q = sel.workQ.toLowerCase();
        const works = arr(d.works);
        const list = works.filter(w => !q || w.name.toLowerCase().includes(q) || w.id.includes(q));
        const w = works.find(x => x.id === sel.work) || works[0];
        if (w) sel.work = w.id;
        if (w && m) usePicker('pick', {
            state: () => arr(d.payers),
            current: () => w.payer,
            choose: it => change('setWork', { work: sel.work, field: 'payer', value: it.spec }),
        });
        let h = head(T('v_gov.page.works')) + `<div class="gv-split"><div><input class="osa-input wide" id="workQ" placeholder="${esc(T('search_work'))}" value="${esc(sel.workQ)}" style="margin-bottom:8px">` +
            `<div class="gv-list">${list.map(x => {
                const p = payerName(d, x.payer);
                return `<a data-act="pickWork" data-id="${esc(x.id)}" class="${x === w ? 'on' : ''}"><span>${esc(x.name)}</span><small>${esc(p.name)}</small></a>`;
            }).join('') || empty()}</div></div>`;
        if (!w) return h + `<div>${empty()}</div></div>`;
        const p = payerName(d, w.payer);
        const keys = Object.keys(d.taxKeys || {}).sort();
        h += `<div class="gv-card"><h2 style="font-size:22px;color:var(--osa-text)">${esc(w.name)} <span class="dim mono" style="font-size:14px">${esc(w.id)}</span></h2>` +
            `<div class="gv-field"><label>${esc(T('payer'))}</label>${pickerBox('pick', p, m, T('search_company'))}</div>` +
            `<div class="gv-field"><label>${esc(T('multiplier'))}</label><div>${edit('wMul', w.multiplier, 'workMul', {}, { allowed: m, unit: '×', reset: 'workMulReset', shown: '×' + w.multiplier })}</div></div>` +
            `<div class="gv-field"><label>${esc(T('tax_key'))}</label><div>${m ? select('wTax', keys.map(k => [k, `${k} (${pct(d.taxKeys[k])})`]), w.taxKey, 'workTax', true)
                : esc(`${w.taxKey} (${pct(w.taxRate)})`)}</div></div>` +
            `<h2 style="margin-top:18px">${esc(T('params'))}</h2>` +
            table([[''], [T('default'), 'r'], [T('value'), 'r']], arr(w.params).map(prm => {
                const v = prm.value !== undefined ? prm.value : prm.default;
                return `<tr><td>${prm.kind === 'xp' ? '<span class="tag">XP</span> ' : ''}${esc(prm.label)}</td><td class="r mono dim">${esc(prm.default)}</td>` +
                    `<td class="r">${edit('prm_' + prm.key, v, 'workParam', { key: prm.key }, { allowed: m, reset: prm.value !== undefined ? 'workParamReset' : null })}</td></tr>`;
            })) + '</div></div>';
        return h;
    };

    PAGE.fees = d => {
        const m = can('minister');
        return head(T('v_gov.page.fees')) + '<div class="gv-card">' +
            table([[''], [T('default'), 'r'], [T('value'), 'r'], [T('tax_target')]], arr(d.fees).map(f =>
                `<tr><td>${esc(T('v_gov.fee.' + f.key))}</td><td class="r mono dim">${money(f.default)}</td>` +
                `<td class="r">${edit('fee_' + f.key.replace(/\./g, '_'), f.value, 'fee', { key: f.key }, { allowed: m, unit: '€', reset: 'feeReset', shown: money(f.value) })}</td>` +
                `<td>${targetPick(d, f.key, m, 'feeTarget', true)}</td></tr>`)) + '</div>';
    };

    PAGE.health = d => {
        const o = can('official');
        const list = Object.entries(d.injuries || {}).sort((a, b) => a[0].localeCompare(b[0]));
        let h = head(T('v_gov.page.health')) + '<div class="gv-card">' +
            `<div class="gv-field"><label>${esc(T('health_enabled'))}</label><div>${toggle(!!d.enabled, 'healthEnabled', {}, o, [T('on'), T('off')])}</div></div>` +
            `<div class="gv-field"><label>${esc(T('hp_price'))}</label><div>${edit('hpPrice', d.hpPrice, 'hpPrice', {}, { allowed: o, unit: '€', shown: money(d.hpPrice) })}</div></div></div>` +
            `<div class="gv-card"><h2>${esc(T('injury_prices'))}</h2>` +
            table([[T('injury_type')], ...[1, 2, 3].map(s => [T('severity_n', { n: s }), 'r']), ['', 'act']], list.map(([type, prices]) => {
                prices = arr(prices);
                return `<tr><td><b>${esc(type)}</b></td>` + [0, 1, 2].map(i => `<td class="r">${edit(`inj_${type}_${i + 1}`, prices[i] || 0, 'injury',
                    { type, sev: i + 1 }, { allowed: o, shown: money(prices[i]) })}</td>`).join('') +
                    `<td class="act">${o && type !== 'default' ? btn(T('delete'), 'removeInjury', { type }, 'danger') : ''}</td></tr>`;
            }));
        if (o) h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="newInjury" placeholder="${esc(T('injury_type'))}" maxlength="24" data-keep="1" data-enter="addInjury">${btn(T('add_injury'), 'addInjury', {}, 'primary')}</div>`;
        return hospitalsCard(d, o) + h + '</div>';
    };

    // who pays the treatment, per hospital: payer (system / the patient / state / private company)
    // and receiver (nobody / state / private company)
    const payerOpts = d => arr(d.payers).map(x => x.spec === 'system' ? { spec: 'system', name: T('payer_system') } : x);
    const receiverOpts = d => arr(d.payers).map(x => x.spec === 'system' ? { spec: 'system', name: T('receiver_none') } : x);
    function healthSpecName(d, spec, side) {
        if (spec === 'player') return { name: T('patient_pays'), tag: '' };
        if (spec === 'system') return { name: side === 'receiver' ? T('receiver_none') : T('payer_system'), tag: '' };
        return payerName(d, spec);
    }
    function hospitalsCard(d, o) {
        const list = arr(d.hospitals);
        const hs = list.find(x => x.id === sel.hospital) || list[0];
        if (hs) sel.hospital = hs.id;
        let h = `<div class="gv-card"><h2>${esc(T('hospitals'))}</h2>`;
        if (!d.hospitalsRunning) h += `<div class="gv-sub" style="margin:-6px 0 10px"><span class="tag bad">${esc(T('hospitals_offline'))}</span></div>`;
        if (!hs) return h + empty() + '</div>';
        if (o) {
            const pick = (side, opts) => usePicker(side === 'payer' ? 'hpPay' : 'hpRecv', {
                state: () => opts,
                current: () => hs[side],
                choose: it => change('setHealth', { field: 'hospital', id: hs.id, side, value: it.spec }),
            });
            pick('payer', [{ spec: 'player', name: T('patient_pays') }, ...payerOpts(d)]);
            pick('receiver', receiverOpts(d));
        }
        const payer = healthSpecName(d, hs.payer, 'payer'), recv = healthSpecName(d, hs.receiver, 'receiver');
        h += `<div class="gv-split"><div class="gv-list">${list.map(x => `<a data-act="pickHospital" data-id="${esc(x.id)}" class="${x === hs ? 'on' : ''}">` +
            `<span>${esc(x.name)}</span><small>${esc(healthSpecName(d, x.payer, 'payer').name)}</small></a>`).join('')}</div>` +
            `<div><h2 style="font-size:20px;color:var(--osa-text)">${esc(hs.name)} <span class="dim mono" style="font-size:13px">${esc(hs.id)}</span></h2>` +
            (hs.missing ? `<div class="gv-sub"><span class="tag bad">${esc(T('hospital_missing'))}</span></div>` : '') +
            (!hs.missing && hs.heal === false ? `<div class="gv-sub">${esc(T('no_heal_marker'))}</div>` : '') +
            `<div class="gv-field"><label>${esc(T('payer'))}</label>${pickerBox('hpPay', payer, o, T('search_payer'))}</div>` +
            `<div class="gv-field"><label>${esc(T('receiver'))}</label>${pickerBox('hpRecv', recv, o, T('search_payer'))}</div>` +
            (hs.payer === 'player' ? `<div class="gv-sub">${esc(T('patient_pays_hint'))}</div>` : '') +
            (o ? `<div class="gv-field"><label></label><div>${btn(T('default_payer'), 'hospitalReset', { id: hs.id })}</div></div>` : '') +
            '</div></div>';
        return h + '</div>';
    }

    // ------------------------------------------------------------ Transfers page
    PAGE.transfers = d => {
        const m = can('minister');
        const states = arr(d.states).filter(s => s.status !== 'closed');
        const opts = states.map(s => [s.id, `${s.name} (${money(s.balance)})`]);
        const amountNote = k => `<input class="osa-input num" id="${k}Amount" placeholder="${esc(T('amount'))}" data-keep="1">` +
            `<input class="osa-input mid" id="${k}Note" placeholder="${esc(T('note'))}" maxlength="48" data-keep="1">`;
        const keepSel = (id, v) => select(id, opts, v, '', true).replace('<select ', '<select data-keep="1" ');
        const coName = c => c ? { name: c.name, tag: 'company' } : { name: T('tf_pick_company'), tag: '' };
        let h = head(T('v_gov.page.transfers'), esc(T('history_note', { days: 30 })));
        if (m) {
            usePicker('tfPay', { state: () => [], current: () => sel.tfPay && sel.tfPay.spec, choose: it => { sel.tfPay = it; render(); } });
            usePicker('tfCol', { state: () => [], current: () => sel.tfCol && sel.tfCol.spec, choose: it => { sel.tfCol = it; render(); } });
            const first = states[0] && states[0].id, second = states[1] ? states[1].id : first;
            h += `<div class="gv-card"><h2>${esc(T('tf_state'))}</h2><div class="gv-row">` +
                `<label class="dim">${esc(T('tf_from'))}</label>${keepSel('tfsFrom', first)}<label class="dim">${esc(T('tf_to'))}</label>${keepSel('tfsTo', second)}</div>` +
                `<div class="gv-row" style="margin-top:10px">${amountNote('tfs')}${btn(T('tf_send'), 'tfSend', { kind: 'state' }, 'primary')}</div></div>` +
                `<div class="gv-card"><h2>${esc(T('tf_pay'))}</h2><div class="gv-field"><label>${esc(T('tf_from'))}</label><div>${keepSel('tfpFrom', first)}</div></div>` +
                `<div class="gv-field"><label>${esc(T('tf_to'))}</label>${pickerBox('tfPay', coName(sel.tfPay), true, T('search_private'))}</div>` +
                `<div class="gv-row" style="margin-top:10px">${amountNote('tfp')}${btn(T('tf_pay_btn'), 'tfSend', { kind: 'pay' }, 'primary')}</div></div>` +
                `<div class="gv-card"><h2>${esc(T('tf_collect'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('tf_collect_hint'))}</div>` +
                `<div class="gv-field"><label>${esc(T('tf_from'))}</label>${pickerBox('tfCol', coName(sel.tfCol), true, T('search_private'))}</div>` +
                `<div class="gv-field"><label>${esc(T('tf_to'))}</label><div>${keepSel('tfcTo', first)}</div></div>` +
                `<div class="gv-row" style="margin-top:10px">${amountNote('tfc')}${btn(T('tf_collect_btn'), 'tfSend', { kind: 'collect' }, 'danger')}</div></div>`;
        } else {
            h += `<div class="gv-card">` + table([[T('account')], [T('balance'), 'r']], states.map(s =>
                `<tr><td>${esc(s.name)} <span class="dim mono">${esc(s.number || '')}</span></td><td class="r mono ${cls(s.balance)}">${money(s.balance)}</td></tr>`)) + '</div>';
        }
        const kindName = a => T({ 'transfer.state': 'tf_state', 'transfer.pay': 'tf_pay', 'transfer.collect': 'tf_collect' }[a] || a);
        return h + `<div class="gv-card"><h2>${esc(T('tf_recent'))}</h2>` +
            table([[T('time')], [T('tf_kind')], [T('tf_from')], [T('tf_to')], [T('amount'), 'r'], [T('note')], [T('actor')]], arr(d.list).map(r => {
                const x = r.detail || {};
                return `<tr><td class="mono dim">${stamp(r.ts)}</td><td>${esc(kindName(r.action))}</td><td>${esc(x.from ?? '')}</td><td>${esc(x.to ?? '')}</td>` +
                    `<td class="r mono">${money(x.amount)}</td><td class="dim">${esc(x.note || '')}</td><td><b>${esc(r.actor)}</b></td></tr>`;
            })) + '</div>';
    };

    PAGE.companies = d => {
        const o = can('official'), m = can('minister');
        const list = arr(d.list);
        const a = D.company && D.company.id === sel.company ? D.company : null;
        let h = head(T('v_gov.page.companies'), null, o ? btn(T('create_company'), 'createCompany', {}, 'primary') : '') +
            `<div class="gv-split"><div class="gv-list">${list.map(c => `<a data-act="pickCompany" data-id="${c.id}" class="${c.id === sel.company ? 'on' : ''}">` +
                `<span>${esc(c.name)}</span><small class="mono ${cls(c.balance)}">${money(c.balance)}</small></a>`).join('') || empty()}</div>`;
        if (!a) return h + `<div class="gv-card dim">${esc(T('empty'))}</div></div>`;
        const pays = arr(d.payers && d.payers[a.code]);
        h += `<div class="gv-card"><div class="gv-head"><div><h1>${esc(a.name)}</h1><div class="gv-sub mono">${esc(a.number || '')} · ${esc(a.code)}` +
            `${a.createdAt ? ` · ${esc(T('created'))} ${stamp(a.createdAt)}` : ''}</div></div>` +
            `<div class="big ${cls(a.balance)}">${money(a.balance)}</div></div>` +
            `<div class="gv-sub" style="margin:8px 0 6px">${esc(T('pays_works', { works: pays.join(', ') || '-' }))}</div>` +
            `<div class="gv-field"><label>${esc(T('company_name'))}</label><div>${edit('cName', a.name, 'renameCompany', {}, { allowed: o, cls: 'mid' })}</div></div>` +
            `<div class="gv-field"><label>${esc(T('company_description'))}</label><div>${edit('cDesc', a.description || '', 'describeCompany', {}, { allowed: o, cls: 'wide', shown: a.description || '-' })}</div></div>` +
            `<div class="gv-field"><label>${esc(T('overdraft'))}</label><div>${toggle(!!a.allowNegative, 'overdraft', {}, m, [T('overdraft_on'), T('overdraft_off')])}</div></div>` +
            (o ? `<div class="gv-field"><label></label><div>${btn(T('delete_company'), 'closeCompany', {}, 'danger')}</div></div>` : '') +
            `<h2 style="margin-top:18px">${esc(T('members'))}</h2>` +
            table([[T('account')], [T('role')], ['', 'act']], arr(a.access).map(x =>
                `<tr><td><b>${esc(x.account)}</b></td><td class="dim">${esc(x.role)}</td><td class="act">${o ? btn(T('remove'), 'companyMemberRemove', { account: x.account }, 'danger') : ''}</td></tr>`));
        if (o) h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="cmAcc" placeholder="${esc(T('account_name'))}" maxlength="64" data-keep="1" data-enter="companyMemberAdd">` +
            select('cmRole', ACC_ROLES.map(r => [r, r]), 'manager', '', true) + btn(T('add_member'), 'companyMemberAdd', {}, 'primary') + '</div>';
        return h + '</div></div>';
    };

    PAGE.budget = d => {
        const rows = arr(d.rows);
        const daily = arr(d.daily);
        const max = Math.max(1, ...daily.map(x => Math.max(x.inSum, x.outSum)));
        const bars = daily.length ? `<div class="gv-bars">${daily.map(x => `<div class="gv-bar" title="${esc(new Date(x.day * 1000).toLocaleDateString('en-GB'))}: +${money(x.inSum)} / -${money(x.outSum)}">` +
            `<i class="in" style="height:${Math.round(x.inSum / max * 100)}%"></i><i class="out" style="height:${Math.round(x.outSum / max * 100)}%"></i></div>`).join('')}</div>` : empty();
        return head(T('v_gov.page.budget'), esc(T('history_note', { days: d.days || 30 }))) +
            `<div class="gv-card"><h2>${esc(T('daily'))} · ${esc(rows[0] ? rows[0].name : '')}</h2>${bars}</div>` +
            rows.map(r => `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(r.name)}</h2><div class="gv-sub mono">${esc(r.code)}</div></div>` +
                `<div class="gv-row"><span class="mono pos">+${money(r.inSum)}</span><span class="mono neg">-${money(r.outSum)}</span>` +
                `<b class="mono ${cls(r.inSum - r.outSum)}">${signed(r.inSum - r.outSum)}</b></div></div>` +
                table([[T('group')], [T('income'), 'r'], [T('expense'), 'r'], [T('net'), 'r']], arr(r.groups).map(g =>
                    `<tr><td>${esc(T('v_bank.group.' + g.group))}</td><td class="r mono pos">+${money(g.inSum)}</td><td class="r mono neg">-${money(g.outSum)}</td>` +
                    `<td class="r mono ${cls(g.inSum - g.outSum)}">${signed(g.inSum - g.outSum)}</td></tr>`)) + '</div>').join('');
    };

    PAGE.votes = d => {
        const m = can('minister');
        const list = arr(d.list);
        const now = Date.now() / 1000;
        const card = v => {
            const opts = arr(v.options);
            const res = arr(v.results);
            const total = res.reduce((t, n) => t + n, 0);
            const best = Math.max(0, ...res);
            const status = v.status === 'open' && v.endsAt <= now ? 'closed' : v.status;
            let body;
            if (v.status === 'closed') {
                body = opts.map((o, i) => {
                    const n = res[i] || 0, p = total ? Math.round(n / total * 1000) / 10 : 0;
                    return `<div class="gv-res${n === best && n > 0 ? ' win' : ''}"><div class="gv-row" style="justify-content:space-between"><span>${esc(o)}` +
                        `${n === best && n > 0 ? ` <span class="tag state">${esc(T('winner'))}</span>` : ''}</span><span class="mono">${n} · ${p}%</span></div>` +
                        `<div class="gv-meter"><i style="width:${p}%"></i></div></div>`;
                }).join('');
            } else {
                body = `<ul class="gv-opts">${opts.map(o => `<li>${esc(o)}</li>`).join('')}</ul>` +
                    (v.status === 'open' ? `<div class="gv-sub">${esc(T('results_after_close'))}</div>` : '');
            }
            return `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(v.title)}</h2>` +
                `<div class="gv-sub"><span class="tag ${status === 'open' ? 'state' : status === 'cancelled' ? 'bad' : ''}">${esc(T('status_' + status))}</span> ` +
                `${esc(T('voters_n', { n: v.voters }))} · ${esc(T('vote_ends'))} ${stamp(v.status === 'open' ? v.endsAt : (v.closedAt || v.endsAt))} · ${esc(v.createdBy)}</div></div>` +
                (m && v.status === 'open' ? `<div class="gv-row">${btn(T('close_vote'), 'closeVote', { id: v.id })}${btn(T('cancel_vote'), 'cancelVote', { id: v.id }, 'danger')}</div>` : '') +
                `</div>${v.description ? `<p class="gv-desc">${esc(v.description)}</p>` : ''}${body}</div>`;
        };
        const open = list.filter(v => v.status === 'open'), done = list.filter(v => v.status !== 'open');
        return head(T('v_gov.page.votes'), null, m ? btn(T('new_vote'), 'newVote', {}, 'primary') : '') +
            `<h2>${esc(T('votes_open'))}</h2>${open.map(card).join('') || empty()}` +
            `<h2 style="margin-top:8px">${esc(T('votes_closed'))}</h2>${done.map(card).join('') || empty()}`;
    };

    PAGE.news = d => {
        const m = can('minister');
        const langs = arr(d.langs);
        const card = n => {
            const texts = n.texts || {};
            const codes = [...langs.map(l => l.value).filter(c => texts[c]), ...Object.keys(texts).filter(c => !langs.some(l => l.value === c))];
            return `<div class="gv-card"><div class="gv-head"><div><div class="gv-sub">${stamp(n.createdAt)} · ${esc(n.createdBy)}` +
                `${n.mailed ? '' : ` <span class="tag bad">${esc(T('news_not_mailed'))}</span>`}</div></div>` +
                (m ? `<div class="gv-row">${btn(T('delete'), 'deleteNews', { id: n.id }, 'danger')}</div>` : '') + '</div>' +
                codes.map(c => `<div style="margin-top:10px"><span class="tag">${esc(c.toUpperCase())}</span> <b>${esc(texts[c].title)}</b>` +
                    `<p class="gv-desc">${esc(texts[c].body)}</p></div>`).join('') + '</div>';
        };
        return head(T('v_gov.page.news'), esc(T('news_hint')), m ? btn(T('new_news'), 'newNews', {}, 'primary') : '') +
            (arr(d.list).map(card).join('') || empty());
    };

    PAGE.members = d => {
        const m = can('minister');
        const roles = ['viewer', 'official', 'minister'].map(r => [r, T('v_gov.role.' + r)]);
        let h = head(T('v_gov.page.members'), esc(T('admins_are_ministers', { level: d.adminLevel || 5 }))) + '<div class="gv-card">';
        if (m) h += `<div class="gv-row" style="margin-bottom:14px"><input class="osa-input mid" id="memAcc" placeholder="${esc(T('account_name'))}" maxlength="64" data-keep="1" data-enter="memberAdd">` +
            select('memRole', roles, 'viewer', '', true) + btn(T('add_member'), 'memberAdd', {}, 'primary') + '</div>';
        h += table([[T('account')], [T('role')], ['', 'act']], arr(d.list).map(x =>
            `<tr><td><b>${esc(x.account)}</b></td><td>${m ? select('mr_' + x.account, roles, x.role, 'memberRole', true).replace('<select ', `<select data-account="${esc(x.account)}" `)
                : esc(T('v_gov.role.' + x.role))}</td><td class="act">${m ? btn(T('remove'), 'memberRemove', { account: x.account }, 'danger') : ''}</td></tr>`));
        return h + '</div>';
    };

    PAGE.log = d => {
        const q = sel.logQ.toLowerCase();
        const list = arr(d.list).filter(r => !q || (r.actor + ' ' + r.action + ' ' + r.detail).toLowerCase().includes(q));
        return head(T('v_gov.page.log'), null, `<input class="osa-input mid" id="logQ" placeholder="${esc(T('filter'))}" value="${esc(sel.logQ)}">`) +
            '<div class="gv-card">' + table([[T('time')], [T('actor')], [T('action')], [T('detail')]], list.map(r =>
                `<tr><td class="mono dim">${stamp(r.ts)}</td><td><b>${esc(r.actor)}</b></td><td style="color:var(--osa-accent)">${esc(r.action)}</td>` +
                `<td class="mono dim" style="word-break:break-all">${esc(r.detail)}</td></tr>`)) + '</div>';
    };

    // ------------------------------------------------------------ payer / company pickers
    // One picker per id (Works payer, hospital payer / receiver, Transfers companies). The state
    // options (opts.state) are filtered locally, private companies are searched on the server
    // (findCompanies, by name or id). Arrow keys + Enter work too. A page calls usePicker(id, opts)
    // while rendering and puts pickerBox(id, ...) in its HTML; render() mounts them.
    const pickers = {};
    let usedPickers = new Set();
    const anyPickerOpen = () => Object.values(pickers).some(p => p.open);
    const hidePickers = () => Object.values(pickers).forEach(p => p.hide());

    // the current choice + the search box ({ name, tag: state | company, inactive })
    const pickerBox = (id, cur, allowed, placeholder) => `<div class="gv-picker" id="${id}"><div class="cur">` +
        `<b>${esc(cur.name)}</b>${cur.tag ? `<span class="tag ${cur.tag}">${esc(cur.tag === 'state' ? T('state_payers') : T('private_companies'))}</span>` : ''}` +
        `${cur.inactive ? `<span class="tag bad">${esc(T('inactive'))}</span>` : ''}</div>` +
        (allowed ? `<input class="osa-input wide" id="${id}Q" placeholder="${esc(placeholder)}" autocomplete="off"><div class="gv-pick-list" id="${id}List" hidden></div>` : '') +
        '</div>';

    function usePicker(id, opts) {
        const p = pickers[id] || (pickers[id] = makePicker(id));
        p.opts = opts;
        usedPickers.add(id);
        return p;
    }
    function mountPickers() {
        for (const id in pickers) if (usedPickers.has(id)) pickers[id].mount(); else pickers[id].open = false;
        usedPickers = new Set();
    }

    function makePicker(id) {
        return {
            id, opts: null, open: false, items: [], hot: -1, timer: null, seq: 0, found: null, loading: false,
            el(suffix) { return $(id + suffix); },
            mount() {
                const q = this.el('Q');
                if (!q) return;
                q.addEventListener('focus', () => this.show());
                q.addEventListener('input', () => { this.hot = -1; this.search(); this.draw(); });
                q.addEventListener('keydown', e => {
                    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                        e.preventDefault();
                        const n = this.items.length;
                        if (n) this.hot = (this.hot + (e.key === 'ArrowDown' ? 1 : n - 1) + (this.hot < 0 && e.key === 'ArrowUp' ? 1 : 0)) % n;
                        this.draw();
                    } else if (e.key === 'Enter') {
                        e.preventDefault();
                        const it = this.items[this.hot >= 0 ? this.hot : 0];
                        if (it) this.choose(it);
                    }
                });
                if (this.open) { this.open = false; this.show(); }
            },
            show() {
                if (!this.el('List')) return;
                hidePickers();
                this.open = true;
                this.el('List').hidden = false;
                this.search();
                this.draw();
            },
            hide() {
                this.open = false;
                if (this.el('List')) this.el('List').hidden = true;
            },
            search() {
                clearTimeout(this.timer);
                const q = (this.el('Q') || {}).value || '';
                this.loading = true;
                const n = ++this.seq;
                this.timer = setTimeout(async () => {
                    let list = [];
                    try { list = arr((await GOV.call('findCompanies', { q: q.trim() })).list); } catch (e) { /* shown as no match */ }
                    if (n !== this.seq) return;
                    this.found = list;
                    this.loading = false;
                    this.draw();
                }, 220);
            },
            draw() {
                const el = this.el('List');
                if (!el || !this.open || !this.opts) return;
                const cur = this.opts.current();
                const q = ((this.el('Q') || {}).value || '').trim().toLowerCase();
                const all = arr(this.opts.state());
                const state = all.filter(p => !q || p.name.toLowerCase().includes(q) || p.spec.includes(q));
                const priv = arr(this.found).map(c => ({ spec: 'company:' + c.id, name: c.name, sub: '#' + c.id }));
                this.items = [...state, ...priv];
                if (this.hot >= this.items.length) this.hot = this.items.length - 1;
                let i = 0;
                const row = it => `<div class="it${i === this.hot ? ' hot' : ''}${cur === it.spec ? ' sel' : ''}" data-i="${i++}">` +
                    `<span>${esc(it.name)}</span><small>${esc(it.sub || (it.spec.startsWith('state:') ? it.spec.slice(6) : ''))}</small></div>`;
                el.innerHTML = (all.length ? `<div class="grp">${esc(T('state_payers'))}</div>` + (state.map(row).join('') || `<div class="none">${esc(T('no_match'))}</div>`) : '') +
                    `<div class="grp">${esc(T('private_companies'))}</div>` +
                    (priv.length ? priv.map(row).join('') : `<div class="none">${esc(this.loading ? T('searching') : T('no_match'))}</div>`);
            },
            async choose(it) {
                this.hide();
                await this.opts.choose(it);
            },
        };
    }
    document.addEventListener('mousedown', e => {
        for (const p of Object.values(pickers)) {
            if (!p.open) continue;
            const it = e.target.closest(`#${p.id}List .it`);
            if (it) { e.preventDefault(); const x = p.items[Number(it.dataset.i)]; if (x) p.choose(x); return; }
            if (!e.target.closest('#' + p.id)) p.hide();
        }
    });

    // ------------------------------------------------------------ actions
    const val = id => ($(id) ? $(id).value.trim() : '');
    const numOf = (id) => {
        const n = num(val(id));
        if (n === null) OSA.toast(T('v_gov.err.bad_number'), false);
        return n;
    };

    const ACT = {
        trAcc: el => { sel.treasury = Number(el.value); load('treasury'); },
        trGroup: el => { sel.group = el.value; load('treasury'); },
        async transfer(b) {
            const n = numOf('trAmount');
            if (n === null) return;
            if (await change('treasuryTransfer', { id: sel.treasury, amount: n, dir: b.dataset.dir, note: val('trNote') })) {
                $('trAmount') && ($('trAmount').value = '');
                $('trNote') && ($('trNote').value = '');
                D.overview = await GOV.call('overview').catch(() => D.overview);
                render();
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
                render();
            } catch (e) { OSA.toast(e.message, false); }
        },
        companyTax() { const n = numOf('companyTax'); if (n !== null) change('setCompanyTax', { value: n }); },
        vat(b) { const n = numOf(b.dataset.input); if (n !== null) change('setVat', { group: b.dataset.group, value: n }); },
        vatReset(b) { change('setVat', { group: b.dataset.group }); },
        propTax() { const n = numOf('propTax'); if (n !== null) change('setPropertyTax', { value: n }); },
        propTaxReset() { change('setPropertyTax', {}); },
        taxTarget: el => change('setTaxTarget', { key: el.dataset.key, code: el.value }),
        feeTarget: el => change('setFeeTarget', { key: el.dataset.key, code: el.value }),
        taxKey(b) { const n = numOf(b.dataset.input); if (n !== null) change('setTaxKey', { key: b.dataset.key, value: n }); },
        async addTaxKey() {
            const n = numOf('newKeyRate');
            if (n === null) return;
            if (await change('setTaxKey', { key: val('newKey'), value: n })) { $('newKey').value = ''; $('newKeyRate').value = ''; }
        },
        deleteTaxKey(b) { change('deleteTaxKey', { key: b.dataset.key }); },
        pickWork(a) { sel.work = a.dataset.id; hidePickers(); render(); },
        pickHospital(a) { sel.hospital = a.dataset.id; hidePickers(); render(); },
        hospitalReset(b) { change('setHealth', { field: 'hospital', id: b.dataset.id, side: 'all' }); },
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
            if (!await OSA.ui.confirm(T('v_gov.page.transfers'), T('confirm_transfer', { amount: money(n), from, to }), T('save'))) return;
            if (await change('moneyTransfer', args)) {
                $(k + 'Amount') && ($(k + 'Amount').value = '');
                $(k + 'Note') && ($(k + 'Note').value = '');
            }
        },
        workMul() { const n = numOf('wMul'); if (n !== null) change('setWork', { work: sel.work, field: 'multiplier', value: n }); },
        workMulReset() { change('setWork', { work: sel.work, field: 'multiplier' }); },
        workTax: el => change('setWork', { work: sel.work, field: 'taxKey', value: el.value }),
        workParam(b) { const n = numOf(b.dataset.input); if (n !== null) change('setWork', { work: sel.work, field: 'param', key: b.dataset.key, value: n }); },
        workParamReset(b) { change('setWork', { work: sel.work, field: 'param', key: b.dataset.key }); },
        fee(b) { const n = numOf(b.dataset.input); if (n !== null) change('setFee', { key: b.dataset.key, value: n }); },
        feeReset(b) { change('setFee', { key: b.dataset.key }); },
        healthEnabled(b) { change('setHealth', { field: 'enabled', value: b.dataset.value === 'true' }); },
        hpPrice() { const n = numOf('hpPrice'); if (n !== null) change('setHealth', { field: 'hp_price', value: n }); },
        injury(b) {
            const n = numOf(b.dataset.input);
            if (n !== null) change('setHealth', { field: 'injury', type: b.dataset.type, severity: Number(b.dataset.sev), value: n });
        },
        removeInjury(b) { change('setHealth', { field: 'remove_injury', type: b.dataset.type }); },
        async addInjury() {
            const t = val('newInjury').toLowerCase();
            if (t && await change('setHealth', { field: 'injury', type: t, severity: 1, value: 0 })) $('newInjury').value = '';
        },
        async pickCompany(a) {
            sel.company = Number(a.dataset.id);
            D.company = null;
            render();
            load('companies');
        },
        async createCompany() {
            const r = await OSA.ui.form(T('create_company'), [
                { name: 'code', label: T('company_code') },
                { name: 'name', label: T('company_name') },
                { name: 'description', label: T('company_description'), type: 'textarea' },
            ], T('create'));
            if (r) change('createCompany', { code: r.code.toLowerCase(), name: r.name, description: r.description, allowNegative: false });
        },
        renameCompany() { if (val('cName')) change('renameCompany', { id: sel.company, name: val('cName') }); },
        describeCompany() { change('describeCompany', { id: sel.company, description: val('cDesc') }); },
        async newVote() {
            const r = await OSA.ui.form(T('new_vote'), [
                { name: 'title', label: T('vote_title') },
                { name: 'description', label: T('vote_description'), type: 'textarea' },
                { name: 'options', label: T('vote_options'), type: 'textarea', placeholder: T('vote_options_hint') },
                { name: 'hours', label: T('vote_hours'), type: 'number', value: '24' },
            ], T('create'));
            if (r) change('openVote', { title: r.title, description: r.description, hours: Number(r.hours),
                options: r.options.split('\n').map(x => x.trim()).filter(Boolean) });
        },
        async newNews() {
            const langs = arr((D.news || {}).langs);
            const draft = sel.newsDraft || {};
            const fields = [];
            for (const l of langs) {
                fields.push({ name: 'title_' + l.value, label: T('news_title') + ' (' + l.label + ')', value: draft['title_' + l.value] });
                fields.push({ name: 'body_' + l.value, label: T('news_body') + ' (' + l.label + ')', type: 'textarea', value: draft['body_' + l.value] });
            }
            const r = await OSA.ui.form(T('new_news'), fields, T('news_send'), T('news_hint'));
            if (!r) return;
            sel.newsDraft = r;   // kept when the server refuses it
            const texts = {};
            for (const l of langs) texts[l.value] = { title: r['title_' + l.value], body: r['body_' + l.value] };
            if (await change('postNews', { texts })) sel.newsDraft = null;
        },
        async deleteNews(b) { if (await OSA.ui.confirm(T('delete'), T('confirm_delete_news'), T('delete'))) change('deleteNews', { id: Number(b.dataset.id) }); },
        async closeVote(b) { if (await OSA.ui.confirm(T('close_vote'), '', T('close_vote'))) change('closeVote', { id: Number(b.dataset.id) }); },
        async cancelVote(b) { if (await OSA.ui.confirm(T('cancel_vote'), '', T('cancel_vote'))) change('cancelVote', { id: Number(b.dataset.id) }); },
        overdraft(b) { change('companyOverdraft', { id: sel.company, allow: b.dataset.value === 'true' }); },
        async closeCompany() {
            const a = D.company;
            if (a && await OSA.ui.confirm(T('delete_company'), T('confirm_close_company', { name: a.name, balance: money(a.balance) }), T('delete_company'))) {
                if (await change('deleteCompany', { id: a.id, move: true })) { sel.company = null; D.company = null; render(); }
            }
        },
        async companyMemberAdd() {
            const acc = val('cmAcc');
            if (acc && await change('companyMember', { id: sel.company, account: acc, role: val('cmRole') })) $('cmAcc').value = '';
        },
        companyMemberRemove(b) { change('companyMember', { id: sel.company, account: b.dataset.account, role: 'none' }); },
        async memberAdd() {
            const acc = val('memAcc');
            if (acc && await change('setMember', { account: acc, role: val('memRole') })) $('memAcc').value = '';
        },
        memberRole: el => change('setMember', { account: el.dataset.account, role: el.value }),
        async memberRemove(b) {
            if (await OSA.ui.confirm(T('remove'), T('confirm_delete', { name: b.dataset.account }), T('remove'))) {
                change('setMember', { account: b.dataset.account, role: 'none' });
            }
        },
    };

    view.addEventListener('click', e => {
        const b = e.target.closest('[data-act]');
        if (!b || b.disabled || !ACT[b.dataset.act]) return;
        ACT[b.dataset.act](b);
    });
    view.addEventListener('change', e => {
        const el = e.target;
        if (el.dataset && el.dataset.change && ACT[el.dataset.change]) ACT[el.dataset.change](el);
    });
    view.addEventListener('keydown', e => {
        const el = e.target;
        if (e.key !== 'Enter' || !el.dataset || !el.dataset.enter) return;
        e.preventDefault();
        const b = view.querySelector(`[data-act="${el.dataset.enter}"][data-input="${el.id}"]`) || view.querySelector(`button[data-act="${el.dataset.enter}"]`);
        if (b && ACT[el.dataset.enter]) ACT[el.dataset.enter](b);
    });
    view.addEventListener('input', e => {
        if (e.target.id === 'workQ') { sel.workQ = e.target.value; render(); }
        else if (e.target.id === 'logQ') { sel.logQ = e.target.value; render(); }
    });

    // ------------------------------------------------------------ start
    if (inGame) mta.triggerEvent('v_gov:pageReady', JSON.stringify([KEYS]));
    else view.innerHTML = '<div class="gv-empty">Open it in game with /gov.</div>';
})();
