// gov_perms - the Permissions page of /gov (see gov_core web/js/gov.js GOV.page): tabs Groups
// (positions: settings, salary, rights tree), Officials (appointments), Branches, Catalogue.
// Reading needs perms.view, changes perms.manage (the Governor / admins); system groups are
// changed by admins only (the server checks every request).
(function () {
    'use strict';
    const { esc, arr, $, money, stamp, val, numOf, head, empty, table, btn, select } = GOV.ui;
    const T = GOV.tr('gov_perms');
    const D = GOV.D, sel = GOV.sel;
    sel.permTab = sel.permTab || 'groups';
    sel.grantDraft = sel.grantDraft || {};   // [group id] = [{ perm, branch }] (unsaved rights)
    sel.catQ = sel.catQ || '';

    const TABS = ['groups', 'officials', 'branches', 'catalogue'];
    const UI = ['tab_groups', 'tab_officials', 'tab_branches', 'tab_catalogue', 'hint', 'new_group', 'group_code', 'group_name',
        'group_description', 'rank', 'max_holders', 'unlimited', 'salary', 'salary_h', 'tax_key', 'color', 'save_group', 'copy_group',
        'archive', 'restore', 'archived', 'system', 'system_hint', 'holders', 'rights', 'rights_hint', 'save_rights', 'reset_rights',
        'unsaved', 'all_targets', 'by_branch', 'targets', 'via', 'patterns', 'patterns_hint', 'add_pattern', 'pattern', 'branch',
        'no_branch', 'danger_0', 'danger_1', 'danger_2', 'danger_3', 'appoint', 'account_name', 'position', 'days', 'days_hint', 'note',
        'appoint_btn', 'dismiss', 'confirm_dismiss', 'replace_holder', 'expires', 'no_end', 'set_expiry', 'paid_30', 'effective',
        'effective_of', 'super', 'from_position', 'branches_hint', 'branch_code', 'branch_name', 'sort', 'companies', 'add_branch',
        'catalogue_hint', 'filter', 'key', 'module', 'area', 'danger', 'active', 'inactive', 'held_by', 'purge', 'confirm_purge',
        'plan_hours', 'plan_hours_hint', 'cost_day', 'cost_total', 'copy_prompt', 'read_only', 'none', 'positions'];
    const AREA_KEYS = ['top', 'economy', 'revenue', 'services', 'employment', 'organizations', 'public', 'admin', 'other'].map(a => 'gov_core.menu.' + a);
    // the names of the rights known when this was written (later modules: the key itself is shown)
    const PERM_KEYS = ['panel.log', 'office.edit', 'companies.create', 'legacy.viewer', 'legacy.official',
        'legacy.minister', 'perms.view', 'perms.manage', 'treasury.overview', 'treasury.transfer.company', 'treasury.collect',
        'treasury.plan.view', 'treasury.plan.edit', 'loans.view', 'tax.view', 'tax.company.edit', 'tax.income.edit', 'tax.vat.edit',
        'tax.property.edit', 'tax.targets.edit', 'fees.view', 'fines.view', 'health.view', 'health.prices.edit', 'transport.view',
        'transport.fares.edit', 'transport.costs.edit', 'rail.view', 'rail.timetable.edit', 'rail.timetable.toggle', 'rail.operator.set',
        'votes.view', 'votes.open', 'votes.close', 'news.view', 'news.post', 'news.delete',
        'gov.*.view', 'gov.*.edit', 'gov.*.close', 'gov.*.bank.view', 'gov.*.bank.pay', 'gov.*.bank.manage', 'gov.*.overdraft',
        'gov.*.standing', 'gov.*.loans', 'fees.*.edit', 'fees.*.target', 'fines.*.edit', 'fines.*.target', 'works.*.view',
        'works.*.pay', 'works.*.payer', 'works.*.multiplier', 'works.*.taxkey', 'health.*.billing'];

    // the same matching as the server (gov_core lib GOV.permMatch)
    const match = (pattern, key) => {
        if (pattern === '*' || pattern === key) return true;
        const p = pattern.split('.'), k = key.split('.');
        for (let i = 0; i < p.length; i++) {
            if (i === p.length - 1 && p[i] === '*') return k.length >= p.length;
            if (k[i] === undefined || (p[i] !== '*' && p[i] !== k[i])) return false;
        }
        return k.length === p.length;
    };
    const companyBranch = (d, key) => {
        const id = (key.match(/^gov\.([^.]+)\./) || [])[1];
        const c = arr(d.companies).find(x => String(x.id) === id);
        return c ? c.branch : null;
    };
    const covers = (d, g, key) => match(g.perm, key) && (!g.branch || companyBranch(d, key) === g.branch);

    // text keys: v_locals keys are a-z 0-9 _ . only, so the "*" of a family is "_" (gov_perms.perm.gov._.bank.pay)
    const textKey = k => 'gov_perms.perm.' + k.replace(/\*/g, '_');
    const permText = r => {
        if (r.family) return GOV.str(textKey(r.family), { target: r.targetName || r.target }) || r.perm;
        return GOV.str(textKey(r.perm)) || r.perm;
    };
    const familyText = f => (GOV.str(textKey(f), { target: '…' }) || f);
    const dangerTag = n => n >= 3 ? `<span class="tag bad">${esc(T('danger_3'))}</span>` : n >= 2 ? `<span class="tag bad" style="opacity:.75">${esc(T('danger_2'))}</span>` : '';
    const dot = c => `<i style="display:inline-block;width:10px;height:10px;border-radius:50%;background:${esc(c || '#888')};margin-right:6px"></i>`;
    const tabs = () => `<div class="gv-row" style="margin-bottom:14px">${TABS.map(t => btn(T('tab_' + t), 'permTab', { tab: t }, sel.permTab === t ? 'primary' : '')).join('')}</div>`;

    // may the player change this group? (perms.manage; system groups: admins)
    const editable = (d, g) => !!d.canManage && (!g || g.kind !== 'system' || d.isAdmin);

    // ------------------------------------------------------------ Groups
    function draftOf(g) {
        if (!sel.grantDraft[g.id]) sel.grantDraft[g.id] = arr(g.grants).map(x => ({ perm: x.perm, branch: x.branch || '' }));
        return sel.grantDraft[g.id];
    }
    const sameGrants = (a, b) => JSON.stringify(arr(a).map(x => x.perm + '|' + (x.branch || '')).sort()) === JSON.stringify(arr(b).map(x => x.perm + '|' + (x.branch || '')).sort());
    const hasExact = (draft, perm, branch) => draft.some(x => x.perm === perm && (x.branch || '') === (branch || ''));

    function rightsTree(d, g, can) {
        const draft = draftOf(g);
        const cat = arr(d.catalogue);
        const statics = cat.filter(r => !r.family);
        const families = {};
        for (const r of cat.filter(r => r.family)) (families[r.family] = families[r.family] || { area: r.area, danger: r.danger, rows: [] }).rows.push(r);
        const branches = arr(d.branches).filter(b => b.status === 'active');
        const box = (checked, perm, branch, disabled) => `<input type="checkbox" data-act="grantToggle" data-perm="${esc(perm)}" data-branch="${esc(branch || '')}"` +
            `${checked ? ' checked' : ''}${disabled || !can ? ' disabled' : ''}>`;
        // a right covered by another grant (a pattern) shows where it comes from
        const via = key => {
            const g2 = draft.find(x => !(x.perm === key && !x.branch) && covers(d, x, key));
            return g2 ? `<span class="dim"> · ${esc(T('via'))} <span class="mono">${esc(g2.perm)}${g2.branch ? ' [' + esc(g2.branch) + ']' : ''}</span></span>` : '';
        };
        let h = '';
        for (const area of arr(d.areas)) {
            const rows = statics.filter(r => r.area === area).sort((a, b) => a.perm.localeCompare(b.perm));
            const fams = Object.entries(families).filter(([, f]) => f.area === area).sort((a, b) => a[0].localeCompare(b[0]));
            if (!rows.length && !fams.length) continue;
            h += `<h3 style="margin:16px 0 6px">${esc(T('gov_core.menu.' + area))}</h3>`;
            h += rows.map(r => `<label class="gv-row" style="gap:8px">${box(hasExact(draft, r.perm), r.perm)}<span>${esc(permText(r))}</span>` +
                `<span class="dim mono">${esc(r.perm)}</span>${dangerTag(r.danger)}${hasExact(draft, r.perm) ? '' : via(r.perm)}</label>`).join('');
            for (const [fam, f] of fams) {
                const all = hasExact(draft, fam, '');
                const isGov = fam.startsWith('gov.*.');
                const picked = f.rows.filter(r => hasExact(draft, r.perm, '')).length;
                const brs = isGov ? branches.filter(b => hasExact(draft, fam, b.code)) : [];
                const summary = all ? T('all_targets') : [brs.length ? brs.map(b => b.name).join(', ') : '', picked ? `${picked}/${f.rows.length}` : ''].filter(Boolean).join(' · ') || T('none');
                h += `<details style="margin:4px 0"${sel.openFam === g.id + fam ? ' open' : ''} data-fam="${esc(fam)}"><summary class="gv-row" style="gap:8px;cursor:pointer">` +
                    `<b>${esc(familyText(fam))}</b><span class="dim mono">${esc(fam)}</span>${dangerTag(f.danger)}<span class="dim">${esc(summary)}</span></summary>` +
                    `<div style="padding:6px 0 6px 22px">` +
                    `<label class="gv-row" style="gap:8px">${box(all, fam, '')}<span>${esc(T('all_targets'))}</span></label>` +
                    (isGov && branches.length ? `<div class="gv-row" style="gap:12px;flex-wrap:wrap"><span class="dim">${esc(T('by_branch'))}</span>` +
                        branches.map(b => `<label class="gv-row" style="gap:4px">${box(hasExact(draft, fam, b.code), fam, b.code, all)}<span>${esc(b.name)}</span></label>`).join('') + '</div>' : '') +
                    `<div class="gv-row" style="gap:12px;flex-wrap:wrap;margin-top:4px"><span class="dim">${esc(T('targets'))}</span>` +
                    f.rows.slice().sort((a, b) => String(a.targetName).localeCompare(String(b.targetName))).map(r => {
                        const exact = hasExact(draft, r.perm, '');
                        const covered = !exact && draft.some(x => covers(d, x, r.perm));
                        return `<label class="gv-row" style="gap:4px">${box(exact || covered, r.perm, '', covered)}<span${covered ? ' class="dim"' : ''}>${esc(r.targetName || r.target)}</span></label>`;
                    }).join('') + '</div></div></details>';
            }
        }
        // grants that are neither a right nor a family: patterns ("rail.*", "gov.*.*" + branch, "*") and inactive keys
        const known = new Set([...statics.map(r => r.perm), ...Object.keys(families), ...cat.filter(r => r.family).map(r => r.perm)]);
        const others = draft.filter(x => !known.has(x.perm) || (x.branch && !Object.keys(families).includes(x.perm)));
        h += `<h3 style="margin:16px 0 6px">${esc(T('patterns'))}</h3><div class="gv-sub" style="margin:-4px 0 8px">${esc(T('patterns_hint'))}</div>` +
            (others.length ? others.map(x => `<div class="gv-row" style="gap:8px"><span class="mono">${esc(x.perm)}</span>` +
                (x.branch ? `<span class="tag">${esc(x.branch)}</span>` : '') +
                (can ? btn(T('remove'), 'grantRemove', { perm: x.perm, branch: x.branch || '' }, 'danger') : '') + '</div>').join('') : `<div class="dim">${esc(T('none'))}</div>`);
        if (can) {
            h += `<div class="gv-row" style="margin-top:8px"><input class="osa-input mid" id="pgPattern_${g.id}" placeholder="${esc(T('pattern'))}" maxlength="64" data-keep="1">` +
                select(`pgPatternBranch_${g.id}`, [['', T('no_branch')], ...branches.map(b => [b.code, b.name])], '', '', true).replace('<select ', '<select data-keep="1" ') +
                btn(T('add_pattern'), 'grantPattern', { id: g.id }) + '</div>';
        }
        return h;
    }

    function groupsTab(d) {
        const groups = arr(d.groups);
        let g = groups.find(x => x.id === sel.permGroup) || groups[0];
        if (g) sel.permGroup = g.id;
        const hours = Number(d.planHours) || 0;
        const costDay = groups.filter(x => x.status === 'active').reduce((t, x) => t + x.salary * x.holders * hours, 0);
        let h = `<div class="gv-split"><div><div class="gv-row" style="margin-bottom:8px">${d.canManage ? btn(T('new_group'), 'groupNew', {}, 'primary') : ''}</div>` +
            `<div class="gv-list">${groups.map(x => `<a data-act="groupPick" data-id="${x.id}" class="${g && x.id === g.id ? 'on' : ''}${x.status !== 'active' ? ' dim' : ''}">` +
                `<span>${dot(x.color)}${esc(x.name)}${x.kind === 'system' ? ` <span class="tag">${esc(T('system'))}</span>` : ''}</span>` +
                `<small class="mono">${x.holders}/${x.maxHolders || '∞'} · ${money(x.salary)}${esc(T('salary_h'))}</small></a>`).join('') || empty()}</div>` +
            // the narrow left column: label, input + Save, hint and the daily cost below each other
            `<div class="gv-card" style="margin-top:10px"><div style="font-weight:600;margin-bottom:6px">${esc(T('plan_hours'))}</div>` +
            (d.canManage ? `<div class="gv-row"><input class="osa-input num" id="pgPlanHours" value="${esc(hours)}" data-orig="${esc(hours)}">` +
                btn(T('save'), 'planHours', {}, 'primary') + '</div>' : `<div class="mono">${esc(hours)}</div>`) +
            `<div class="gv-sub" style="margin-top:6px">${esc(T('plan_hours_hint'))}</div>` +
            `<div class="gv-sub" style="margin-top:6px">${esc(T('cost_total', { amount: money(costDay) }))}</div></div></div>`;
        if (!g) return h + `<div class="gv-card dim">${esc(T('empty'))}</div></div>`;
        const can = editable(d, g);
        const keys = Object.keys(d.taxKeys || {}).sort();
        const holders = arr(d.members).filter(m => m.groupId === g.id);
        const names = d.names || {};
        const draft = draftOf(g);
        const dirty = !sameGrants(draft, g.grants);
        const inp = (id, v, cls, extra) => can ? `<input class="osa-input ${cls || 'mid'}" id="${id}_${g.id}" value="${esc(v)}" data-keep="1"${extra || ''}>` : `<span>${esc(v)}</span>`;
        h += `<div class="gv-card"><div class="gv-head"><div><h1>${dot(g.color)}${esc(g.name)}</h1><div class="gv-sub mono">${esc(g.code)} · #${g.id}` +
            `${g.kind === 'system' ? ' · ' + esc(T('system')) : ''}${g.status !== 'active' ? ' · ' + esc(T('archived')) : ''}</div></div>` +
            `<div class="gv-row">${can && g.kind !== 'system' ? btn(T('copy_group'), 'groupCopy', { id: g.id }) : ''}` +
            (can && g.kind !== 'system' ? btn(T(g.status === 'active' ? 'archive' : 'restore'), 'groupStatus', { id: g.id, archived: g.status === 'active' ? 'true' : 'false' }, g.status === 'active' ? 'danger' : '') : '') + '</div></div>' +
            (g.kind === 'system' ? `<div class="gv-sub" style="margin:6px 0">${esc(T('system_hint'))}</div>` : '') +
            (!can && d.canManage ? `<div class="gv-sub" style="margin:6px 0">${esc(T('read_only'))}</div>` : '') +
            `<div class="gv-field"><label>${esc(T('group_name'))}</label><div>${inp('pgName', g.name, 'mid', ' maxlength="64"')}</div></div>` +
            `<div class="gv-field"><label>${esc(T('group_description'))}</label><div>${inp('pgDesc', g.description || '', 'wide', ' maxlength="255"')}</div></div>` +
            `<div class="gv-field"><label>${esc(T('rank'))}</label><div>${inp('pgRank', g.rank, 'num')}</div></div>` +
            `<div class="gv-field"><label>${esc(T('max_holders'))}</label><div>${inp('pgMax', g.maxHolders, 'num')} <span class="dim">${esc(T('unlimited'))}</span></div></div>` +
            `<div class="gv-field"><label>${esc(T('salary'))}</label><div>${can ? inp('pgSalary', g.salary, 'num') + `<span class="gv-unit">€${esc(T('salary_h'))}</span>` : money(g.salary) + esc(T('salary_h'))}` +
            ` <span class="dim">${esc(T('paid_30'))}: ${money(g.paid30)}</span></div></div>` +
            `<div class="gv-field"><label>${esc(T('tax_key'))}</label><div>${can ? select('pgTax_' + g.id, keys.map(k => [k, `${k} (${Math.round((d.taxKeys[k] || 0) * 1000) / 10}%)`]), g.taxKey, '', true).replace('<select ', '<select data-keep="1" ') : esc(g.taxKey)}</div></div>` +
            `<div class="gv-field"><label>${esc(T('color'))}</label><div>${can ? `<input type="color" id="pgColor_${g.id}" value="${esc(g.color)}" data-keep="1">` : dot(g.color)}</div></div>` +
            (can ? `<div class="gv-field"><label></label><div>${btn(T('save_group'), 'groupSave', { id: g.id }, 'primary')}</div></div>` : '') +
            `<h2 style="margin-top:18px">${esc(T('holders'))}</h2>` +
            (holders.length ? holders.map(m => `<div class="gv-row"><b>${esc(names[m.account] || m.account)}</b><span class="dim mono">${esc(m.account)}</span>` +
                `<span class="dim">${m.expiresAt ? esc(T('expires')) + ' ' + stamp(m.expiresAt) : esc(T('no_end'))}</span></div>`).join('') : `<div class="dim">${esc(T('none'))}</div>`) +
            `<h2 style="margin-top:18px">${esc(T('rights'))}${dirty ? ` <span class="tag bad">${esc(T('unsaved'))}</span>` : ''}</h2>` +
            `<div class="gv-sub" style="margin:-6px 0 10px">${esc(T('rights_hint'))}</div>` +
            (can ? `<div class="gv-row" style="margin-bottom:8px">${btn(T('save_rights'), 'grantSave', { id: g.id }, 'primary')}${btn(T('reset_rights'), 'grantReset', { id: g.id })}</div>` : '') +
            rightsTree(d, g, can) + '</div>';
        return h + '</div>';
    }

    // ------------------------------------------------------------ Officials
    function officialsTab(d) {
        const groups = arr(d.groups);
        const names = d.names || {};
        const byAcc = {};
        for (const m of arr(d.members)) (byAcc[m.account] = byAcc[m.account] || []).push(m);
        const accounts = Object.keys(byAcc).sort((a, b) => String(names[a] || a).localeCompare(String(names[b] || b)));
        const groupOf = id => groups.find(g => g.id === id) || { name: '#' + id, color: '#888', kind: '' };
        let h = '';
        if (d.canManage) {
            const opts = groups.filter(g => g.status === 'active' && (g.kind !== 'system' || d.isAdmin))
                .map(g => [g.id, `${g.name} (${g.holders}/${g.maxHolders || '∞'})`]);
            h += `<div class="gv-card"><h2>${esc(T('appoint'))}</h2><div class="gv-row">` +
                `<input class="osa-input mid" id="apAcc" placeholder="${esc(T('account_name'))}" maxlength="64" data-keep="1">` +
                select('apGroup', opts, opts[0] && opts[0][0], '', true).replace('<select ', '<select data-keep="1" ') +
                `<input class="osa-input num" id="apDays" placeholder="${esc(T('days'))}" data-keep="1">` +
                `<input class="osa-input mid" id="apNote" placeholder="${esc(T('note'))}" maxlength="128" data-keep="1">` +
                btn(T('appoint_btn'), 'appoint', {}, 'primary') + `</div><div class="gv-sub" style="margin-top:6px">${esc(T('days_hint'))}</div></div>`;
        }
        h += '<div class="gv-card">' + table([[T('account_name')], [T('positions')], [T('paid_30'), 'r'], ['', 'act']], accounts.map(acc =>
            `<tr><td><b>${esc(names[acc] || acc)}</b><br><span class="dim mono">${esc(acc)}</span></td><td>` +
            byAcc[acc].map(m => {
                const g = groupOf(m.groupId);
                const can = d.canManage && (g.kind !== 'system' || d.isAdmin);
                return `<div class="gv-row" style="gap:6px">${dot(g.color)}<span>${esc(g.name)}</span>` +
                    `<span class="dim">${m.expiresAt ? esc(T('expires')) + ' ' + stamp(m.expiresAt) : esc(T('no_end'))}</span>` +
                    (m.note ? `<span class="dim">· ${esc(m.note)}</span>` : '') +
                    (can ? btn(T('set_expiry'), 'memberExpiry', { id: m.id }) + btn(T('dismiss'), 'dismiss', { id: m.id, name: names[acc] || acc, group: g.name }, 'danger') : '') + '</div>';
            }).join('') + `</td><td class="r mono">${money((d.paid || {})[acc] || 0)}</td>` +
            `<td class="act">${btn(T('effective'), 'effective', { account: acc })}</td></tr>`)) + '</div>';
        const e = D.permEffective;
        if (e && e.account) {
            h += `<div class="gv-card"><h2>${esc(T('effective_of', { name: names[e.account] || e.account }))}</h2>` +
                `<div class="gv-sub" style="margin:-6px 0 10px">${esc(arr(e.positions).join(', ') || '-')}${e.super ? ' · ' + esc(T('super')) : ''}</div>` +
                table([[T('key')], [''], [T('from_position')]], arr(e.rows).map(r => {
                    const c = arr(d.catalogue).find(x => x.perm === r.perm) || { perm: r.perm };
                    return `<tr><td class="mono">${esc(r.perm)}</td><td>${esc(permText(c))}</td><td class="dim">${esc(r.group)}</td></tr>`;
                })) + '</div>';
        }
        return h;
    }

    // ------------------------------------------------------------ Branches
    function branchesTab(d) {
        let h = `<div class="gv-card"><div class="gv-sub" style="margin:0 0 10px">${esc(T('branches_hint'))}</div>` +
            table([[T('branch_code')], [T('branch_name')], [T('sort'), 'r'], [T('companies'), 'r'], ['', 'act']], arr(d.branches).map(b =>
                `<tr${b.status !== 'active' ? ' class="dim"' : ''}><td class="mono">${esc(b.code)}</td>` +
                `<td>${d.canManage ? `<input class="osa-input mid" id="brName_${esc(b.code)}" value="${esc(b.name)}" data-keep="1">` : esc(b.name)}</td>` +
                `<td class="r">${d.canManage ? `<input class="osa-input num" id="brSort_${esc(b.code)}" value="${esc(b.sort)}" data-keep="1">` : b.sort}</td>` +
                `<td class="r mono">${b.companies}</td><td class="act">${d.canManage ? btn(T('save'), 'branchSave', { code: b.code }, 'primary') +
                    (b.code !== 'other' ? btn(T(b.status === 'active' ? 'archive' : 'restore'), 'branchStatus', { code: b.code, archived: b.status === 'active' ? 'true' : 'false' }) : '') : ''}</td></tr>`));
        if (d.canManage) {
            h += `<div class="gv-row" style="margin-top:14px"><input class="osa-input mid" id="brNewCode" placeholder="${esc(T('branch_code'))}" maxlength="24" data-keep="1">` +
                `<input class="osa-input mid" id="brNewName" placeholder="${esc(T('branch_name'))}" maxlength="64" data-keep="1">` +
                `<input class="osa-input num" id="brNewSort" placeholder="${esc(T('sort'))}" data-keep="1">` + btn(T('add_branch'), 'branchAdd', {}, 'primary') + '</div>';
        }
        return h + '</div>';
    }

    // ------------------------------------------------------------ Catalogue
    function catalogueTab(d) {
        const rows = arr(D.permCatalogue);
        const q = sel.catQ.toLowerCase();
        const groups = arr(d.groups);
        const heldBy = key => groups.filter(g => g.status === 'active' && arr(g.grants).some(x => covers(d, x, key))).map(g => g.name).join(', ');
        const list = rows.filter(r => !q || (r.perm + ' ' + permText(r) + ' ' + r.module).toLowerCase().includes(q));
        return `<div class="gv-card"><div class="gv-row" style="margin-bottom:10px"><input class="osa-input mid" id="catQ" placeholder="${esc(T('filter'))}" value="${esc(sel.catQ)}">` +
            `<span class="dim">${esc(T('catalogue_hint'))}</span></div>` +
            table([[T('area')], [''], [T('key')], [T('module')], [T('danger')], [T('held_by')], ['', 'act']], list.map(r =>
                `<tr${r.active ? '' : ' class="dim"'}><td>${esc(T('gov_core.menu.' + r.area))}</td><td>${esc(permText(r))}</td><td class="mono">${esc(r.perm)}</td>` +
                `<td class="dim">${esc(r.module)}</td><td>${dangerTag(r.danger) || esc(T('danger_' + r.danger))}</td>` +
                `<td class="dim">${esc(heldBy(r.perm))}</td><td class="act">${r.active ? '' : `<span class="tag">${esc(T('inactive'))}</span>` +
                    (d.canManage ? btn(T('purge'), 'purge', { perm: r.perm }, 'danger') : '')}</td></tr>`)) + '</div>';
    }

    // ------------------------------------------------------------ the page
    GOV.page('perms', {
        keys: [...GOV.keys('gov_perms', UI), ...AREA_KEYS, ...PERM_KEYS.map(textKey)],
        async load() {
            const r = await GOV.call('perms');
            if (sel.permTab === 'catalogue') D.permCatalogue = arr((await GOV.call('permCatalogue')).list);
            return r;
        },
        render(d) {
            const body = { groups: groupsTab, officials: officialsTab, branches: branchesTab, catalogue: catalogueTab }[sel.permTab] || groupsTab;
            return head(GOV.title('perms'), esc(T('hint'))) + tabs() + body(d);
        },
        actions: {
            permTab(b) { sel.permTab = b.dataset.tab; GOV.render(); GOV.load('perms'); },
            groupPick(a) { sel.permGroup = Number(a.dataset.id); GOV.render(); },
            async groupNew() {
                const r = await OSA.ui.form(T('new_group'), [
                    { name: 'code', label: T('group_code') },
                    { name: 'name', label: T('group_name') },
                ], T('save_group'));
                if (!r) return;
                try {
                    const res = await GOV.call('saveGroup', { code: r.code.toLowerCase(), name: r.name, rank: 100, maxHolders: 0, salary: 0, taxKey: 'standard' });
                    sel.permGroup = res.id;
                    OSA.toast(T('saved'), true);
                } catch (e) { OSA.toast(e.message, false); }
                GOV.load('perms');
            },
            async groupSave(b) {
                const id = Number(b.dataset.id);
                const g = arr((D.perms || {}).groups).find(x => x.id === id);
                if (!g) return;
                const rank = numOf('pgRank_' + id), max = numOf('pgMax_' + id), salary = numOf('pgSalary_' + id);
                if (rank === null || max === null || salary === null) return;
                await GOV.change('saveGroup', { id, name: val('pgName_' + id), description: val('pgDesc_' + id), rank, maxHolders: max, salary,
                    taxKey: val('pgTax_' + id) || g.taxKey, color: val('pgColor_' + id) || g.color });
            },
            async groupCopy(b) {
                const r = await OSA.ui.form(T('copy_group'), [
                    { name: 'code', label: T('group_code') },
                    { name: 'name', label: T('group_name') },
                ], T('copy_group'), T('copy_prompt'));
                if (!r) return;
                try {
                    const res = await GOV.call('copyGroup', { id: Number(b.dataset.id), code: r.code.toLowerCase(), name: r.name });
                    sel.permGroup = res.id;
                    OSA.toast(T('saved'), true);
                } catch (e) { OSA.toast(e.message, false); }
                GOV.load('perms');
            },
            groupStatus(b) { GOV.change('setGroupStatus', { id: Number(b.dataset.id), archived: b.dataset.archived === 'true' }); },
            grantToggle(el) {
                const g = arr((D.perms || {}).groups).find(x => x.id === sel.permGroup);
                if (!g) return;
                const draft = draftOf(g);
                const perm = el.dataset.perm, branch = el.dataset.branch || '';
                const i = draft.findIndex(x => x.perm === perm && (x.branch || '') === branch);
                if (i >= 0) draft.splice(i, 1); else draft.push({ perm, branch });
                const det = el.closest('details');
                sel.openFam = det ? g.id + det.dataset.fam : null;
                GOV.render();
            },
            grantRemove(b) {
                const g = arr((D.perms || {}).groups).find(x => x.id === sel.permGroup);
                if (!g) return;
                const draft = draftOf(g);
                const i = draft.findIndex(x => x.perm === b.dataset.perm && (x.branch || '') === (b.dataset.branch || ''));
                if (i >= 0) draft.splice(i, 1);
                GOV.render();
            },
            grantPattern(b) {
                const id = Number(b.dataset.id);
                const g = arr((D.perms || {}).groups).find(x => x.id === id);
                const perm = val('pgPattern_' + id);
                if (!g || !perm) return;
                const branch = val('pgPatternBranch_' + id);
                const draft = draftOf(g);
                if (!hasExact(draft, perm, branch)) draft.push({ perm, branch });
                $('pgPattern_' + id).value = '';
                GOV.render();
            },
            async grantSave(b) {
                const id = Number(b.dataset.id);
                const g = arr((D.perms || {}).groups).find(x => x.id === id);
                if (!g) return;
                const draft = draftOf(g);
                const cat = arr((D.perms || {}).catalogue);
                const risky = draft.filter(x => !hasExact(g.grants, x.perm, x.branch) && cat.some(r => r.danger >= 3 && covers(D.perms, x, r.perm)));
                if (risky.length && !await OSA.ui.confirm(T('rights'), T('danger_3') + ': ' + risky.map(x => x.perm).join(', '), T('save_rights'))) return;
                if (await GOV.change('setGroupGrants', { id, grants: draft })) delete sel.grantDraft[id];
            },
            grantReset(b) { delete sel.grantDraft[Number(b.dataset.id)]; GOV.render(); },
            planHours() { const n = numOf('pgPlanHours'); if (n !== null) GOV.change('setPlanHours', { value: n }); },
            async appoint() {
                const d = D.perms || {};
                const acc = val('apAcc'), group = Number(val('apGroup'));
                const days = val('apDays') === '' ? 0 : numOf('apDays');
                if (!acc || !group || days === null) return;
                const g = arr(d.groups).find(x => x.id === group);
                let replace = false;
                if (g && g.maxHolders === 1 && g.holders >= 1) {
                    if (!await OSA.ui.confirm(T('appoint'), T('replace_holder', { position: g.name }), T('appoint_btn'))) return;
                    replace = true;
                }
                if (await GOV.change('appoint', { account: acc, group, days, note: val('apNote'), replace })) {
                    for (const id of ['apAcc', 'apDays', 'apNote']) if ($(id)) $(id).value = '';
                }
            },
            async dismiss(b) {
                if (await OSA.ui.confirm(T('dismiss'), T('confirm_dismiss', { name: b.dataset.name, position: b.dataset.group }), T('dismiss'))) {
                    GOV.change('dismiss', { id: Number(b.dataset.id) });
                }
            },
            async memberExpiry(b) {
                const r = await OSA.ui.form(T('set_expiry'), [{ name: 'days', label: T('days'), placeholder: '0' }], T('save'), T('days_hint'));
                if (!r) return;
                const n = r.days === '' ? 0 : GOV.ui.num(r.days);
                if (n === null) return OSA.toast(T('gov_core.err.bad_number'), false);
                GOV.change('setExpiry', { id: Number(b.dataset.id), days: n });
            },
            async effective(b) {
                try {
                    D.permEffective = await GOV.call('permEffective', { account: b.dataset.account });
                    GOV.render();
                } catch (e) { OSA.toast(e.message, false); }
            },
            branchSave(b) {
                const code = b.dataset.code;
                const sort = numOf('brSort_' + code);
                if (sort !== null) GOV.change('saveBranch', { code, name: val('brName_' + code), sort });
            },
            branchStatus(b) { GOV.change('setBranchStatus', { code: b.dataset.code, archived: b.dataset.archived === 'true' }); },
            async branchAdd() {
                const sort = val('brNewSort') === '' ? 100 : numOf('brNewSort');
                if (sort === null) return;
                if (await GOV.change('saveBranch', { code: val('brNewCode').toLowerCase(), name: val('brNewName'), sort })) {
                    for (const id of ['brNewCode', 'brNewName', 'brNewSort']) if ($(id)) $(id).value = '';
                }
            },
            async purge(b) {
                if (await OSA.ui.confirm(T('purge'), T('confirm_purge', { perm: b.dataset.perm }), T('purge'))) GOV.change('purgePerm', { perm: b.dataset.perm });
            },
        },
        input: { catQ(el) { sel.catQ = el.value; GOV.render(); } },
    });
})();
