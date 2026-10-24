// gov_core - the /gov panel shell: side menu (grouped by category), request bridge, page loading,
// dialogs and the shared building blocks / pickers. The pages come from the running gov_*
// modules: the server sends their list on open, the shell loads their scripts
// (/<module>/<script>) and every script registers its pages:
//
//   GOV.page(id, { keys: [...full text keys], load?: async () => data, render: d => html,
//                  actions: { name(el) {...} }, input: { elementId(el) {...} } })
//
//   GOV.call(action, args) -> Promise<result>   (rejects with the translated error text)
//   GOV.tr(ns) -> T(key, params): <ns>.ui.<key>, else gov_core.ui.<key>, a full key as it is
//
// Texts come from v_locals: the shell asks the core keys on start (pageReady -> _init), the
// page titles, category names and page keys once the scripts are loaded (pageStrings -> _strings).
(function () {
    'use strict';
    const esc = OSA.esc;
    const arr = OSA.arr;
    const $ = id => document.getElementById(id);
    const view = $('view');

    const ROLE_LEVEL = { viewer: 1, official: 2, minister: 3 };
    const CORE_KEYS = [
        ...['title', 'loading', 'empty', 'saved', 'delete', 'reset', 'save', 'close', 'value', 'default', 'account', 'amount',
            'note', 'balance', 'time', 'description', 'total', 'actor', 'action', 'detail', 'filter', 'income', 'expense',
            'group', 'net', 'role', 'remove', 'add_member', 'account_name', 'create', 'on', 'off', 'inactive', 'confirm_delete',
            'search_company', 'state_payers', 'private_companies', 'no_match', 'searching', 'payer', 'receiver', 'payer_system',
            'receiver_none', 'patient_pays', 'search_payer', 'search_private', 'private_company', 'history_note', 'period',
            'companies', 'created', 'tax_key', 'tax_runs']
            .map(k => 'gov_core.ui.' + k),
        ...['viewer', 'official', 'minister', 'sector'].map(r => 'gov_core.role.' + r),
        'gov_core.err.bad_number',
    ];
    let STR = {};
    const tr = ns => (key, params) => {
        let full = key;
        if (!key.includes('.')) full = STR[ns + '.ui.' + key] !== undefined ? ns + '.ui.' + key : 'gov_core.ui.' + key;
        let s = STR[full];
        if (s === undefined) s = full.split('.').pop().replace(/_/g, ' ');
        return params ? String(s).replace(/\{(\w+)\}/g, (m, k) => params[k] ?? m) : String(s);
    };
    const T = tr('gov_core');

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

    // per player, in the page's own storage (may be missing: private mode, blocked storage)
    const store = {
        get(k, d) { try { const v = localStorage.getItem('gov_core.' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
        set(k, v) { try { localStorage.setItem('gov_core.' + k, JSON.stringify(v)); } catch (e) { /* not kept */ } },
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
        mta.triggerEvent('gov_core:pageCall', id, action, JSON.stringify([args || {}]));
    });
    GOV._resolve = (id, result, error) => {
        const w = waiting[id];
        delete waiting[id];
        if (!w) return;
        if (result === false) w.reject(new Error(error || 'Error'));
        else w.resolve(result);
    };

    let role = 'viewer';
    let sectors = [];          // the sectors the player's company runs (gov_core GOV.inSector)
    const can = need => (ROLE_LEVEL[role] || 0) >= ROLE_LEVEL[need];
    // the change actions of a sector: ministers, or a member of the company that runs it
    const canSector = id => can('minister') || sectors.includes(id);

    // ------------------------------------------------------------ pages of the modules
    const PAGE = {};           // id -> def (GOV.page)
    const ACT = {};            // action name -> handler (every page's actions)
    let MENU = [];             // { id, res, category, order, need, script, title } in menu order
    let CATS = [];             // { id, order, key }

    GOV.page = (id, def) => {
        PAGE[id] = def;
        for (const [name, fn] of Object.entries(def.actions || {})) {
            if (ACT[name]) console.warn('gov: action handler ' + name + ' already exists');
            else ACT[name] = fn;
        }
    };
    GOV.keys = (ns, list) => list.map(k => ns + '.ui.' + k);
    GOV.tr = tr;

    const version = new URLSearchParams(location.search).get('v') || String(Date.now());
    const loadScript = src => new Promise(resolve => {
        const s = document.createElement('script');
        s.src = src + '?v=' + encodeURIComponent(version);
        s.onload = () => resolve(true);
        s.onerror = () => { console.warn('gov: could not load ' + src); resolve(false); };
        document.body.appendChild(s);
    });

    GOV._init = async data => {
        role = data.role || 'viewer';
        sectors = arr(data.sectors);
        STR = data.strings || {};
        MENU = arr(data.pages);
        CATS = arr(data.categories);
        $('title').textContent = T('title');
        $('role').textContent = T('gov_core.role.' + role);
        $('closeBtn').textContent = T('close') + ' (Esc)';
        document.title = T('title');
        await Promise.all([...new Set(MENU.map(p => '/' + p.res + '/' + p.script))].map(loadScript));
        const keys = new Set();
        for (const p of MENU) {
            keys.add(p.title);
            for (const k of arr(PAGE[p.id] && PAGE[p.id].keys)) keys.add(k);
        }
        for (const c of CATS) keys.add(c.key);
        mta.triggerEvent('gov_core:pageStrings', JSON.stringify([[...keys]]));
    };

    GOV._strings = strings => {
        Object.assign(STR, strings || {});
        MENU = MENU.filter(p => PAGE[p.id]);
        if (!MENU.length) { view.innerHTML = `<div class="gv-empty">${esc(T('empty'))}</div>`; return; }
        const last = store.get('lastPage', null);
        show(MENU.some(p => p.id === last) ? last : MENU[0].id);
    };

    function close() { if (inGame) mta.triggerEvent('gov_core:pageClose'); }
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
    let page = null;
    const D = {};             // data per page
    const sel = {};           // the pages' selections (kept while the panel is open)
    let busy = false;
    const collapsed = store.get('collapsed', {});
    const pageTitle = id => { const p = MENU.find(x => x.id === id); return T(p ? p.title : id); };

    // categories in order, each with its pages; "top" has no header; the open page's category is
    // always expanded
    function nav() {
        let h = '';
        for (const c of CATS) {
            const ps = MENU.filter(p => p.category === c.id);
            if (!ps.length) continue;
            const open = c.id === 'top' || !collapsed[c.id] || ps.some(p => p.id === page);
            if (c.id !== 'top') h += `<div class="gv-cat${open ? ' open' : ''}" data-cat="${esc(c.id)}"><span>${esc(T(c.key))}</span><i>${open ? '▾' : '▸'}</i></div>`;
            if (open) h += ps.map(p => `<a data-page="${esc(p.id)}" class="${p.id === page ? 'on' : ''}">${esc(T(p.title))}</a>`).join('');
        }
        $('nav').innerHTML = h;
    }
    $('nav').addEventListener('click', e => {
        const a = e.target.closest('a[data-page]');
        if (a) return show(a.dataset.page);
        const c = e.target.closest('[data-cat]');
        if (!c) return;
        collapsed[c.dataset.cat] = c.classList.contains('open');
        store.set('collapsed', collapsed);
        nav();
    });

    function show(p) {
        if (!PAGE[p]) return;
        page = p;
        store.set('lastPage', p);
        hidePickers();
        nav();
        if (!D[p]) view.innerHTML = `<h1>${esc(pageTitle(p))}</h1><div class="gv-empty">${esc(T('loading'))}</div>`;
        else render();
        load(p);
    }

    async function load(p) {
        p = p || page;
        const def = PAGE[p];
        if (!def) return;
        try {
            D[p] = def.load ? await def.load() : await GOV.call(p);
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
        if (!page || !PAGE[page]) return;
        const vals = {};
        for (const el of view.querySelectorAll('input[id], select[id]')) if (el.classList.contains('dirty') || el.dataset.keep) vals[el.id] = el.value;
        const focus = document.activeElement && document.activeElement.id;
        const scroll = view.scrollTop;
        view.innerHTML = PAGE[page].render(D[page] || {});
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
    const runsTable = runs => table([[T('period')], [T('companies'), 'r'], [T('total'), 'r']],
        arr(runs).map(r => `<tr><td class="mono">${stamp(r.period)}</td><td class="r">${r.companies}</td><td class="r mono pos">${money(r.total)}</td></tr>`));

    function mark(el) {
        if (el.dataset.orig !== undefined) el.classList.toggle('dirty', el.value !== el.dataset.orig);
    }
    view.addEventListener('input', e => mark(e.target));

    // payer / receiver names of a spec ("system" | "player" | "state:<code>" | "company:<id>")
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
    const payerOpts = d => arr(d.payers).map(x => x.spec === 'system' ? { spec: 'system', name: T('payer_system') } : x);
    const receiverOpts = d => arr(d.payers).map(x => x.spec === 'system' ? { spec: 'system', name: T('receiver_none') } : x);
    function specName(d, spec, side) {
        if (spec === 'player') return { name: T('patient_pays'), tag: '' };
        if (spec === 'system') return { name: side === 'receiver' ? T('receiver_none') : T('payer_system'), tag: '' };
        return payerName(d, spec);
    }

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

    // ------------------------------------------------------------ the toolkit of the page scripts
    const val = id => ($(id) ? $(id).value.trim() : '');
    const numOf = id => {
        const n = num(val(id));
        if (n === null) OSA.toast(T('gov_core.err.bad_number'), false);
        return n;
    };

    GOV.D = D;
    GOV.sel = sel;
    GOV.can = can;
    GOV.canSector = canSector;
    GOV.load = load;
    GOV.change = change;
    GOV.render = render;
    GOV.title = pageTitle;
    GOV.hidePickers = hidePickers;
    GOV.usePicker = usePicker;
    GOV.pickerBox = pickerBox;
    GOV.ui = { esc, arr, $, money, signed, cls, pct, stamp, num, val, numOf, head, kpi, empty, table, btn, edit, toggle, select,
        runsTable, payerName, payerOpts, receiverOpts, specName };

    // ------------------------------------------------------------ events of the pages
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
        const def = PAGE[page];
        const fn = def && def.input && def.input[e.target.id];
        if (fn) fn(e.target);
    });

    // ------------------------------------------------------------ start
    if (inGame) mta.triggerEvent('gov_core:pageReady', JSON.stringify([CORE_KEYS]));
    else view.innerHTML = '<div class="gv-empty">Open it in game with /gov.</div>';
})();
