// gov_core - the pages of gov_core itself: State companies, Log (see gov.js GOV.page). The officials
// and their rights are on gov_perms' Permissions page.
(function () {
    'use strict';
    const { esc, arr, money, cls, stamp, val, empty, table, btn, edit, toggle, select, head } = GOV.ui;
    const T = GOV.tr('gov_core');
    const D = GOV.D, sel = GOV.sel;

    // ------------------------------------------------------------ State companies
    GOV.page('companies', {
        keys: GOV.keys('gov_core', ['create_company', 'company_code', 'company_name', 'company_description', 'pays_works',
            'overdraft', 'overdraft_on', 'overdraft_off', 'delete_company', 'members', 'members_hint', 'confirm_close_company',
            'branch']),
        async load() {
            const r = await GOV.call('companies');
            if (sel.company && arr(r.list).some(c => c.id === sel.company)) D.company = (await GOV.call('company', { id: sel.company })).company;
            else sel.company = null;
            return r;
        },
        render(d) {
            const list = arr(d.list);
            const branches = arr(d.branches);
            const branchName = code => (branches.find(b => b.code === code) || {}).name || code;
            const a = D.company && D.company.id === sel.company ? D.company : null;
            let h = head(GOV.title('companies'), null, GOV.can('companies.create') ? btn(T('create_company'), 'createCompany', {}, 'primary') : '') +
                `<div class="gv-split"><div class="gv-list">${list.map(c => `<a data-act="pickCompany" data-id="${c.id}" class="${c.id === sel.company ? 'on' : ''}">` +
                    `<span>${esc(c.name)}<br><small class="dim">${esc(branchName(c.branch))}</small></span><small class="mono ${cls(c.balance)}">${money(c.balance)}</small></a>`).join('') || empty()}</div>`;
            if (!a) return h + `<div class="gv-card dim">${esc(T('empty'))}</div></div>`;
            const edits = GOV.can('gov.' + a.id + '.edit');
            const pays = arr(d.payers && d.payers[a.code]);
            h += `<div class="gv-card"><div class="gv-head"><div><h1>${esc(a.name)}</h1><div class="gv-sub mono">${esc(a.number || '')} · ${esc(a.code)} · #${a.id}` +
                `${a.createdAt ? ` · ${esc(T('created'))} ${stamp(a.createdAt)}` : ''}</div></div>` +
                `<div class="big ${cls(a.balance)}">${money(a.balance)}</div></div>` +
                `<div class="gv-sub" style="margin:8px 0 6px">${esc(T('pays_works', { works: pays.join(', ') || '-' }))}</div>` +
                `<div class="gv-field"><label>${esc(T('company_name'))}</label><div>${edit('cName', a.name, 'renameCompany', {}, { allowed: edits, cls: 'mid' })}</div></div>` +
                `<div class="gv-field"><label>${esc(T('company_description'))}</label><div>${edit('cDesc', a.description || '', 'describeCompany', {}, { allowed: edits, cls: 'wide', shown: a.description || '-' })}</div></div>` +
                `<div class="gv-field"><label>${esc(T('branch'))}</label><div>${GOV.can('perms.manage')
                    ? select('cBranch', branches.map(b => [b.code, b.name]), a.branch, 'companyBranch', true) : esc(branchName(a.branch))}</div></div>` +
                `<div class="gv-field"><label>${esc(T('overdraft'))}</label><div>${toggle(!!a.allowNegative, 'overdraft', {}, GOV.can('gov.' + a.id + '.overdraft'), [T('overdraft_on'), T('overdraft_off')])}</div></div>` +
                (GOV.can('gov.' + a.id + '.close') ? `<div class="gv-field"><label></label><div>${btn(T('delete_company'), 'closeCompany', {}, 'danger')}</div></div>` : '') +
                `<h2 style="margin-top:18px">${esc(T('members'))}</h2><div class="gv-sub" style="margin:-6px 0 10px">${esc(T('members_hint'))}</div>` +
                table([[T('account')], [T('role')]], arr(a.access).map(x => `<tr><td><b>${esc(x.account)}</b></td><td class="dim">${esc(x.role)}</td></tr>`));
            return h + '</div></div>';
        },
        actions: {
            async pickCompany(a) {
                sel.company = Number(a.dataset.id);
                D.company = null;
                GOV.render();
                GOV.load('companies');
            },
            async createCompany() {
                const fields = [
                    { name: 'code', label: T('company_code') },
                    { name: 'name', label: T('company_name') },
                    { name: 'description', label: T('company_description'), type: 'textarea' },
                ];
                const branches = arr((D.companies || {}).branches);
                if (GOV.can('perms.manage') && branches.length) {
                    fields.push({ name: 'branch', label: T('branch'), type: 'select', value: 'other', options: branches.map(b => ({ value: b.code, label: b.name })) });
                }
                const r = await OSA.ui.form(T('create_company'), fields, T('create'));
                if (r) GOV.change('createCompany', { code: r.code.toLowerCase(), name: r.name, description: r.description, branch: r.branch || 'other', allowNegative: false });
            },
            renameCompany() { if (val('cName')) GOV.change('renameCompany', { id: sel.company, name: val('cName') }); },
            describeCompany() { GOV.change('describeCompany', { id: sel.company, description: val('cDesc') }); },
            companyBranch(el) { GOV.change('setCompanyBranch', { id: sel.company, branch: el.value }); },
            overdraft(b) { GOV.change('companyOverdraft', { id: sel.company, allow: b.dataset.value === 'true' }); },
            async closeCompany() {
                const a = D.company;
                if (a && await OSA.ui.confirm(T('delete_company'), T('confirm_close_company', { name: a.name, balance: money(a.balance) }), T('delete_company'))) {
                    if (await GOV.change('deleteCompany', { id: a.id, move: true })) { sel.company = null; D.company = null; GOV.render(); }
                }
            },
        },
    });

    // ------------------------------------------------------------ Log
    sel.logQ = sel.logQ || '';
    GOV.page('log', {
        keys: [],
        render(d) {
            const q = sel.logQ.toLowerCase();
            const list = arr(d.list).filter(r => !q || (r.actor + ' ' + r.action + ' ' + r.detail).toLowerCase().includes(q));
            return head(GOV.title('log'), null, `<input class="osa-input mid" id="logQ" placeholder="${esc(T('filter'))}" value="${esc(sel.logQ)}">`) +
                '<div class="gv-card">' + table([[T('time')], [T('actor')], [T('action')], [T('detail')]], list.map(r =>
                    `<tr><td class="mono dim">${stamp(r.ts)}</td><td><b>${esc(r.actor)}</b></td><td style="color:var(--osa-accent)">${esc(r.action)}</td>` +
                    `<td class="mono dim" style="word-break:break-all">${esc(r.detail)}</td></tr>`)) + '</div>';
        },
        input: { logQ(el) { sel.logQ = el.value; GOV.render(); } },
    });
})();
