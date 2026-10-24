// gov_core - the pages of gov_core itself: State companies, Members, Log (see gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, $, money, cls, stamp, val, empty, table, btn, edit, toggle, select, head } = GOV.ui;
    const T = GOV.tr('gov_core');
    const D = GOV.D, sel = GOV.sel;
    const ACC_ROLES = ['manager', 'viewer', 'owner'];
    const ROLES = ['viewer', 'official', 'minister'];

    // ------------------------------------------------------------ State companies
    GOV.page('companies', {
        keys: GOV.keys('gov_core', ['create_company', 'company_code', 'company_name', 'company_description', 'pays_works',
            'overdraft', 'overdraft_on', 'overdraft_off', 'delete_company', 'members', 'confirm_close_company']),
        async load() {
            const r = await GOV.call('companies');
            if (sel.company) D.company = (await GOV.call('company', { id: sel.company })).company;
            return r;
        },
        render(d) {
            const o = GOV.can('official'), m = GOV.can('minister');
            const list = arr(d.list);
            const a = D.company && D.company.id === sel.company ? D.company : null;
            let h = head(GOV.title('companies'), null, o ? btn(T('create_company'), 'createCompany', {}, 'primary') : '') +
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
        },
        actions: {
            async pickCompany(a) {
                sel.company = Number(a.dataset.id);
                D.company = null;
                GOV.render();
                GOV.load('companies');
            },
            async createCompany() {
                const r = await OSA.ui.form(T('create_company'), [
                    { name: 'code', label: T('company_code') },
                    { name: 'name', label: T('company_name') },
                    { name: 'description', label: T('company_description'), type: 'textarea' },
                ], T('create'));
                if (r) GOV.change('createCompany', { code: r.code.toLowerCase(), name: r.name, description: r.description, allowNegative: false });
            },
            renameCompany() { if (val('cName')) GOV.change('renameCompany', { id: sel.company, name: val('cName') }); },
            describeCompany() { GOV.change('describeCompany', { id: sel.company, description: val('cDesc') }); },
            overdraft(b) { GOV.change('companyOverdraft', { id: sel.company, allow: b.dataset.value === 'true' }); },
            async closeCompany() {
                const a = D.company;
                if (a && await OSA.ui.confirm(T('delete_company'), T('confirm_close_company', { name: a.name, balance: money(a.balance) }), T('delete_company'))) {
                    if (await GOV.change('deleteCompany', { id: a.id, move: true })) { sel.company = null; D.company = null; GOV.render(); }
                }
            },
            async companyMemberAdd() {
                const acc = val('cmAcc');
                if (acc && await GOV.change('companyMember', { id: sel.company, account: acc, role: val('cmRole') })) $('cmAcc').value = '';
            },
            companyMemberRemove(b) { GOV.change('companyMember', { id: sel.company, account: b.dataset.account, role: 'none' }); },
        },
    });

    // ------------------------------------------------------------ Members
    GOV.page('members', {
        keys: GOV.keys('gov_core', ['admins_are_ministers']),
        render(d) {
            const m = GOV.can('minister');
            const roles = ROLES.map(r => [r, T('gov_core.role.' + r)]);
            let h = head(GOV.title('members'), esc(T('admins_are_ministers', { level: d.adminLevel || 5 }))) + '<div class="gv-card">';
            if (m) h += `<div class="gv-row" style="margin-bottom:14px"><input class="osa-input mid" id="memAcc" placeholder="${esc(T('account_name'))}" maxlength="64" data-keep="1" data-enter="memberAdd">` +
                select('memRole', roles, 'viewer', '', true) + btn(T('add_member'), 'memberAdd', {}, 'primary') + '</div>';
            h += table([[T('account')], [T('role')], ['', 'act']], arr(d.list).map(x =>
                `<tr><td><b>${esc(x.account)}</b></td><td>${m ? select('mr_' + x.account, roles, x.role, 'memberRole', true).replace('<select ', `<select data-account="${esc(x.account)}" `)
                    : esc(T('gov_core.role.' + x.role))}</td><td class="act">${m ? btn(T('remove'), 'memberRemove', { account: x.account }, 'danger') : ''}</td></tr>`));
            return h + '</div>';
        },
        actions: {
            async memberAdd() {
                const acc = val('memAcc');
                if (acc && await GOV.change('setMember', { account: acc, role: val('memRole') })) $('memAcc').value = '';
            },
            memberRole: el => GOV.change('setMember', { account: el.dataset.account, role: el.value }),
            async memberRemove(b) {
                if (await OSA.ui.confirm(T('remove'), T('confirm_delete', { name: b.dataset.account }), T('remove'))) {
                    GOV.change('setMember', { account: b.dataset.account, role: 'none' });
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
