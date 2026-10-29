// OrgOS - the organization computer. One page, several apps (side menu). The
// state comes from biz_pc:pcState(unit) every few seconds; actions go through
// biz_pc:pcAction(unit, action, args).
//
// The office computer manages the company (Overview, Finance, Properties,
// Settings). A site computer manages only that site: the weed farm has
// Overview / Supply / Stock / Sales / Upgrades, the casino Overview / Laundering, and both
// end with Sell property. Pictures come from biz_core: img/buildings/<building>.jpg
// and img/upgrades/<image>.jpg.
(function () {
    'use strict';
    const api = OSA.api();
    const esc = OSA.esc;
    const $ = id => document.getElementById(id);
    const q = new URLSearchParams(location.search);
    const UNIT = Number(q.get('unit')) || 0;
    const IMG = '/biz_core/img/';

    const ERRORS = {
        no_access: 'Only the founder can use this computer.',
        no_company: 'You have no organization.',
        not_enough_money: 'Not enough money.',
        not_enough_dirty: 'Not enough unlaundered money.',
        bad_amount: 'Enter a valid amount.',
        unavailable: 'The service is not available right now.',
        name_short: 'The name is too short.', name_long: 'The name is too long.',
        name_invalid: 'The name contains characters that are not allowed.',
        name_taken: 'That name is taken.', name_same: 'That is the current name.',
        rename_cooldown: 'The organization was renamed recently. Try again later.',
        already_owned: 'You already own it.', use_move_hq: 'Offices are changed by moving the headquarters.',
        cannot_sell_hq: 'The headquarters cannot be sold. Move it first.',
        activity_offline: 'This business is not available right now.',
        confirm_mismatch: 'Type the exact name of the organization to confirm.',
        mission_running: 'A mission of this property is running. Finish it first.',
        mission_cooldown: 'Wait a little before the next mission.',
        no_product: 'There is no product to sell.', no_space: 'There is no room for more supply.',
        not_enough_product: 'Not enough product.', too_many: 'That is more than you can deliver now.',
        paused: 'The business is stopped: pay the upkeep first (deposit money in the office).',
        no_casino: 'Laundering needs a casino.', pending: 'An order is already on its way.',
        unknown_upgrade: 'Unknown upgrade.', in_vehicle: 'Get out of the vehicle first.',
        wrong_computer: 'Use the computer in your office for that.',
    };
    const errText = r => (r && ERRORS[r.error]) || (r && r.error ? 'Failed: ' + r.error : 'Something went wrong.');
    const money = n => (n < 0 ? '−€ ' : '€ ') + Math.abs(Math.round(Number(n) || 0)).toLocaleString('en-US');
    const signed = n => (n > 0 ? '+' : '') + money(n);
    const pct = n => Math.round((Number(n) || 0) * 100) + '%';
    const dur = s => {
        s = Math.max(0, Math.round(s || 0));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return h ? `${h} h ${m} min` : (m ? `${m} min` : `${s % 60} s`);
    };
    const stamp = ts => {
        const d = new Date(ts * 1000);
        return d.toLocaleDateString('en-GB', { month: '2-digit', day: '2-digit' }) + ' ' +
            d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    };
    const cap = s => s ? s[0].toUpperCase() + s.slice(1) : '';
    const CAT = {
        'property.buy': 'Property', 'property.sell': 'Property', 'property.refund': 'Property', 'property.upgrade': 'Upgrade',
        'weed.sale': 'Weed · sale', 'weed.supply': 'Weed · supply', 'casino.hour': 'Casino', launder: 'Laundering',
        upkeep: 'Upkeep', deposit: 'Deposit', withdrawal: 'Withdrawal', rename: 'Rename', founded: 'Founded',
        'admin.adjust': 'Admin', 'admin.rename': 'Admin', 'company.sell': 'Sale',
        tax: 'Tax', transfer: 'Transfer', wages: 'Wages', opening: 'Opening balance',
    };
    const KIND = { office: 'Office', weed: 'Weed farm', casino: 'Casino' };

    // inline icons (a <use href="#id"> breaks under the loader's <base>)
    const ICON_PATHS = {
        overview: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>',
        finance: '<rect x="2.5" y="6" width="19" height="13" rx="2"/><path d="M2.5 10h19M16 15h2.5"/>',
        properties: '<path d="M4 21V5l8-3v19M12 8l8 3v10M2 21h20M7.5 8v1M7.5 12v1M7.5 16v1M16 14v1M16 17.5v1"/>',
        settings: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',
        supply: '<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/>',
        sales: '<path d="M2 6h12v10H2zM14 9.5h4.5L22 13v3h-8z"/><circle cx="6" cy="17.5" r="2"/><circle cx="17.5" cy="17.5" r="2"/>',
        sell: '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.5"/>',
        launder: '<path d="M20 12a8 8 0 0 1-14.2 5M4 12a8 8 0 0 1 14.2-5M18.5 3v4h-4M5.5 21v-4h4M12 8v8M14 9.5h-3a1.5 1.5 0 0 0 0 3h2a1.5 1.5 0 0 1 0 3h-3"/>',
        power: '<path d="M12 3v8M6.3 7a8 8 0 1 0 11.4 0"/>',
        upgrades: '<path d="M12 20V9M7.5 13.5 12 9l4.5 4.5M5 4h14"/>',
        check: '<path d="m5 12.5 4.5 4.5L19 7.5" stroke-width="3"/>',
    };
    const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICON_PATHS[name] || ''}</svg>`;

    // picture with a quiet fallback: a missing file leaves the tinted frame
    const img = (path, alt) => `<img src="${esc(IMG + path)}" alt="${esc(alt || '')}" onerror="this.classList.add('noimg')">`;
    const buildingImg = (building, alt) => building ? img(`buildings/${building}.jpg`, alt) : '';

    let S = null;          // last state
    let tab = 'overview';
    let busy = false;

    // ------------------------------------------------------------ frame
    // in game the client closes the PC and tells the server itself: no pcClose call into a
    // browser that is being destroyed (its answer also closed a PC reopened meanwhile)
    function close() {
        if (window.mta && mta.triggerEvent) { mta.triggerEvent('bizpc:pageClose'); return; }
        api.call('pcClose').catch(() => {});
    }
    $('closeBtn').insertAdjacentHTML('afterbegin', icon('power'));
    $('closeBtn').addEventListener('click', close);
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape' && !document.querySelector('.osa-modal-back:not([hidden])')) close();
    });
    const tick = () => { $('clock').textContent = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); };
    tick();
    setInterval(tick, 1000);

    const kind = () => (S && S.unit ? S.unit.kind : 'office');

    // side menu per computer kind: [id, label, icon] | ['sep']
    function apps() {
        if (kind() === 'weed') return [['overview', 'Overview', 'overview'], ['supply', 'Supply / Stock', 'supply'], ['sales', 'Sales', 'sales'], ['upgrades', 'Upgrades', 'upgrades'], ['sep'], ['sell', 'Sell property', 'sell']];
        if (kind() === 'casino') return [['overview', 'Overview', 'overview'], ['launder', 'Laundering', 'launder'], ['sep'], ['sell', 'Sell property', 'sell']];
        return [['overview', 'Overview', 'overview'], ['finance', 'Finance', 'finance'], ['properties', 'Properties', 'properties'], ['settings', 'Settings', 'settings']];
    }

    function nav() {
        $('nav').innerHTML = apps().map(([id, label, ic]) => id === 'sep' ? '<div class="sep"></div>'
            : `<a data-tab="${id}" class="${id === tab ? 'on' : ''}${id === 'sell' ? ' danger' : ''}">${icon(ic)}${esc(label)}</a>`).join('');
        for (const a of $('nav').querySelectorAll('a')) a.addEventListener('click', () => { tab = a.dataset.tab; render(); });
    }

    async function act(action, args, okText) {
        if (busy) return null;
        busy = true;
        let r;
        try { r = await api.call('pcAction', UNIT, action, args || {}); } catch (e) { r = null; }
        busy = false;
        if (!r || !r.ok) OSA.toast(errText(r), false);
        else if (okText) OSA.toast(okText, true);
        await refresh();
        return r;
    }

    // keeps typed values across re-renders
    function keepInputs(fn) {
        const vals = {};
        for (const el of document.querySelectorAll('#view input, #view select')) if (el.id) vals[el.id] = el.value;
        const focus = document.activeElement && document.activeElement.id;
        const scroll = $('view').scrollTop;
        fn();
        for (const id in vals) { const el = $(id); if (el) el.value = vals[id]; }
        if (focus && $(focus)) $(focus).focus();
        $('view').scrollTop = scroll;
    }

    // ------------------------------------------------------------ building blocks
    function kpi(k, v, cls, sub, extra) {
        return `<div class="os-kpi"><div class="k">${esc(k)}</div><div class="v ${cls || ''}">${v}</div>${extra || ''}${sub ? `<div class="s">${sub}</div>` : ''}</div>`;
    }
    const bar = (value, max, cls) => `<div class="os-bar ${cls || ''}"><i style="width:${max ? Math.min(100, Math.round(value / max * 100)) : 0}%"></i></div>`;
    const pill = (text, cls, dot) => `<span class="pill ${cls}">${dot === false ? '' : '<i></i>'}${esc(text)}</span>`;

    function head(title, sub, right) {
        return `<div class="os-head"><div><h1>${esc(title)}</h1>${sub ? `<div class="sub">${sub}</div>` : ''}</div>${right || ''}</div>`;
    }

    function companyPill() {
        return S.company.paused ? pill('Stopped · upkeep unpaid', 'bad') : pill('Running', 'ok');
    }

    // photo header of a site computer
    function banner(statusPill) {
        const u = S.unit;
        const p = catalogEntry(u.propertyId);
        const city = p.city ? ' · ' + esc(p.city) : '';
        return `<div class="banner">${buildingImg(u.building, u.name)}<div class="bt"><div><h1>${esc(u.name)}</h1>
            <div class="sub">${esc(KIND[u.kind] || u.kind)}${u.illegal ? ' · Illegal' : ''}${city} · ${esc(S.company.name)}</div></div>${statusPill}</div></div>`;
    }

    function ledgerTable(rows) {
        rows = OSA.arr(rows);
        if (!rows.length) return '<div class="os-empty">No transactions yet.</div>';
        return `<table class="os-table"><tr><th>Date</th><th>Category</th><th>Description</th><th class="num">Amount</th><th class="num">Balance</th></tr>` +
            rows.map(r => `<tr><td>${stamp(r.ts)}</td><td>${esc(CAT[r.category] || r.category)}${r.dirty ? '<span class="os-tag">dirty</span>' : ''}</td>
                <td>${esc(r.description)}</td><td class="num ${r.amount > 0 ? 'pos' : (r.amount < 0 ? 'neg' : '')}">${r.amount ? signed(r.amount) : '–'}</td>
                <td class="num">${money(r.balance)}</td></tr>`).join('') + '</table>';
    }

    // hides table rows that do not fit their card (the overview never scrolls)
    function fitRows(card) {
        if (!card) return;
        const rows = card.querySelectorAll('tr');
        const limit = card.getBoundingClientRect().bottom - 18;
        for (let i = rows.length - 1; i > 0; i--) {
            if (rows[i].getBoundingClientRect().bottom <= limit) break;
            rows[i].hidden = true;
        }
    }

    function catalogEntry(propertyId) {
        return OSA.arr(S.catalog).find(p => p.id === propertyId) || {};
    }

    function typeLine(p) {
        const parts = [KIND[p.kind] || cap(p.kind)];
        if (p.tier) parts.push(cap(p.tier));
        if (p.illegal) parts.push('Illegal');
        if (p.city) parts.push(p.city);
        return parts.join(' · ');
    }

    // ------------------------------------------------------------ office apps
    const VIEWS = {};
    const OFFICE = {}, WEED = {}, CASINO = {};

    OFFICE.overview = () => {
        const c = S.company;
        const units = OSA.arr(c.units);
        const assoc = OSA.arr(c.associates);
        const hq = units.find(u => u.id === c.hqUnit);
        const slots = [];
        for (let i = assoc.length; i < c.maxAssociates && slots.length < 1; i++) slots.push('<div class="person"><span class="av empty"></span><span style="color:var(--osa-faint)">Invite on your phone</span></div>');
        return `${head(c.name, hq ? `Headquarters: ${esc(hq.name)}${catalogEntry(hq.propertyId).city ? ', ' + esc(catalogEntry(hq.propertyId).city) : ''}` : '', companyPill())}
        <div class="os-kpis">
            ${kpi('Balance', money(c.balance), '', `clean ${money(c.clean)} · <span class="dirty">dirty ${money(c.dirty)}</span>`)}
            ${kpi('Income · 7 days', signed(S.income7), 'pos', 'sales, casino hours')}
            ${kpi('Expenses · 7 days', money(-S.expenses7), 'neg', 'upkeep, supply, upgrades')}
            ${kpi('Company value', money(c.value), '', `sale now: ${money(c.salePayout)}`)}
        </div>
        ${c.paused ? `<div class="os-warn">The upkeep could not be paid: production and the casino are stopped until the company account covers ${money(c.upkeepAmount)}.</div>` : ''}
        <div class="os-row" style="grid-template-columns: 1fr 1fr 1.25fr">
            <div class="os-card"><h2>Upkeep</h2>
                <p>Every property and the office cost ${money(c.upkeepAmount)} every 2 hours of your online time.</p>
                <div class="big">Next payment in ${dur(c.upkeepIn)}</div>
                ${bar(S.config.upkeepInterval - c.upkeepIn, S.config.upkeepInterval)}</div>
            <div class="os-card"><h2>Associates <small>${assoc.length} / ${c.maxAssociates} online</small></h2>
                ${assoc.map(a => { const n = OSA.clean(a.name); return `<div class="person"><span class="av">${esc(n.slice(0, 1).toUpperCase())}</span><span>${esc(n)}</span></div>`; }).join('')}
                ${slots.join('')}</div>
            <div class="os-card"><h2>Properties <small>${units.length} owned</small></h2>
                ${units.map(u => `<div class="person"><span class="th">${buildingImg(u.building)}</span><span>${esc(u.name)}</span>
                    <small>${u.id === c.hqUnit ? 'HQ · office' : esc(KIND[u.kind] || u.kind)}</small></div>`).join('')}</div>
        </div>
        <div class="os-card grow" id="txCard"><h2>Latest transactions <small>Finance: full ledger</small></h2>${ledgerTable(OSA.arr(S.ledger).slice(0, 10))}</div>`;
    };
    OFFICE.overview.bind = () => fitRows($('txCard'));

    OFFICE.finance = () => {
        const c = S.company;
        return `${head('Finance', 'Money between your bank account and the company account.', companyPill())}
        <div class="os-kpis k3">
            ${kpi('Clean balance', money(c.clean))}
            ${kpi('Unlaundered (dirty)', money(c.dirty), 'dirty', c.launder ? `${money(c.launder)} waiting for laundering` : 'launder it in a casino')}
            ${kpi('Your bank account', money(S.bank))}
        </div>
        <div class="os-row c2">
            <div class="os-card"><h2>Deposit</h2><p>From your bank account to the company account.</p>
                <div class="os-flex"><input class="input" id="depAmount" type="number" min="1" placeholder="Amount" style="width:220px">
                <button class="btn primary" id="depBtn">Deposit</button></div></div>
            <div class="os-card"><h2>Withdraw</h2><p>From the company account to your bank account.</p>
                <div class="os-flex"><input class="input" id="wdAmount" type="number" min="1" placeholder="Amount" style="width:220px">
                <select class="input" id="wdPart"><option value="clean">Clean money</option><option value="dirty">Dirty money</option></select>
                <button class="btn primary" id="wdBtn">Withdraw</button></div>
                <div class="os-note" style="margin-top:14px">Clean money goes to your bank account. Dirty money is paid out in cash only, and unlaundered money may have consequences later. Launder it in a casino first.</div></div>
        </div>
        <div class="os-card"><h2>Ledger
            <select class="input" id="ledFilter" style="font-size:16px;height:42px">
                <option value="">All categories</option><option value="weed">Weed</option><option value="casino">Casino</option>
                <option value="launder">Laundering</option><option value="upkeep">Upkeep</option><option value="property">Properties</option>
                <option value="deposit">Deposits</option><option value="withdrawal">Withdrawals</option>
                <option value="tax">Taxes</option><option value="transfer">Transfers</option></select></h2>
            <div id="ledger">${ledgerTable(S.ledger)}</div></div>`;
    };
    OFFICE.finance.bind = () => {
        $('depBtn').onclick = () => act('deposit', { amount: Number($('depAmount').value) }, 'Deposited').then(r => { if (r && r.ok) $('depAmount').value = ''; });
        $('wdBtn').onclick = () => act('withdraw', { amount: Number($('wdAmount').value), part: $('wdPart').value }, 'Withdrawn').then(r => { if (r && r.ok) $('wdAmount').value = ''; });
        $('ledFilter').onchange = async () => {
            let r;
            try { r = await api.call('pcAction', UNIT, 'ledger', { category: $('ledFilter').value }); } catch (e) { r = null; }
            $('ledger').innerHTML = r && r.ok ? ledgerTable(r.rows) : esc(errText(r));
        };
    };

    // property cards: picture, name, type and a big price - no hover details
    function propCard(p, priceHtml, attrs, owned) {
        return `<div class="prop${owned ? ' owned' : ''}" ${attrs || ''}><div class="ph">${buildingImg(p.building, p.name)}</div>
            <div class="pb"><div class="nm">${esc(p.name)}</div><div class="ty">${esc(typeLine(p))}</div>${priceHtml}</div></div>`;
    }

    OFFICE.properties = () => {
        const c = S.company;
        const owned = OSA.arr(c.units);
        const ownedIds = new Set(owned.map(u => u.propertyId));
        const buyable = OSA.arr(S.catalog).filter(p => p.kind !== 'office' && !ownedIds.has(p.id));
        return `${head('Properties', 'Sites are managed and sold on their own computer.', companyPill())}
        <div class="sect">Your properties</div>
        <div class="props">${owned.map(u => propCard(Object.assign({}, catalogEntry(u.propertyId), u),
            `<div class="pr own">${u.id === c.hqUnit ? 'Headquarters' : 'Owned'}</div>`, '', true)).join('')}</div>
        <div class="sect">Available</div>
        ${buyable.length ? `<div class="props">${buyable.map(p => propCard(p, `<div class="pr">${money(p.gross ?? p.price)}</div>`,
            `data-buy="${esc(p.id)}" data-name="${esc(p.name)}" data-price="${p.gross ?? p.price}" data-upkeep="${p.upkeep}"`)).join('')}</div>`
            : '<div class="os-empty">You own every available property. Offices are changed on sabusinessregistry.eu.</div>'}`;
    };
    OFFICE.properties.bind = () => {
        for (const b of document.querySelectorAll('[data-buy]')) b.onclick = async () => {
            if (await OSA.ui.confirm('Buy property', `Buy ${b.dataset.name} for ${money(b.dataset.price)} from the company account? Upkeep: ${money(b.dataset.upkeep)} every 2 hours online.`, 'Buy'))
                act('buy', { propertyId: b.dataset.buy }, 'Purchase started');
        };
    };

    OFFICE.settings = () => {
        const c = S.company;
        const wait = c.renameWait > 0 ? `<p>Next rename possible in ${dur(c.renameWait)}.</p>` : '';
        return `${head('Settings', '', companyPill())}
        <div class="os-row c2">
            <div class="os-card"><h2>Name</h2><p>Renaming costs ${money(c.renameCost)} from the company account.</p>${wait}
                <div class="os-flex"><input class="input" id="newName" maxlength="32" placeholder="${esc(c.name)}" style="width:320px">
                <button class="btn primary" id="renameBtn">Rename</button></div></div>
            <div class="os-card"><h2>Headquarters</h2><p>Move your headquarters on sabusinessregistry.eu (in-game browser). The old office is bought back at half its price.</p></div>
        </div>
        <div class="os-card"><h2>Sell the organization</h2>
            <p>The organization ends. You get the full balance (${money(c.balance)}) and ${pct(S.config.saleRatio)} of the properties, upgrades and stock (${money(c.assets)}).</p>
            <div class="big">Payout now: ${money(c.salePayout)}</div>
            <div class="os-flex" style="margin-top:14px"><input class="input" id="sellConfirm" placeholder="Type the organization name" style="width:320px">
            <button class="btn danger" id="sellBtn">Sell organization</button></div></div>`;
    };
    OFFICE.settings.bind = () => {
        $('renameBtn').onclick = () => act('rename', { name: $('newName').value.trim() }, 'Renaming…');
        $('sellBtn').onclick = async () => {
            const name = $('sellConfirm').value.trim();
            if (name !== S.company.name) return OSA.toast(ERRORS.confirm_mismatch, false);
            if (!await OSA.ui.confirm('Sell organization', `Sell ${S.company.name} for ${money(S.company.salePayout)}? This cannot be undone.`, 'Sell')) return;
            const r = await act('sellorg', { confirm: name }, 'Organization sold');
            if (r && r.ok) setTimeout(close, 1500);
        };
    };

    // ------------------------------------------------------------ sell property (every site)
    // this unit with its refund / stock value (company.units) over the plain unit data
    function siteUnit() {
        const own = OSA.arr(S.company.units).find(u => u && u.id === S.unit.id);
        return Object.assign({}, S.unit, typeof own === 'object' ? own : {});
    }

    function sellView() {
        const u = siteUnit();
        const a = S.activity;
        const lost = [];
        if (a && a.kind === 'weed') {
            if (a.supply) lost.push(`supply (${a.supply})`);
            if (a.product) lost.push(`product (${a.product}, worth ${money(a.productValue)})`);
        }
        const mission = a && a.mission;
        return `${head('Sell property', 'The money goes to the company account.')}
        <div class="os-row grow" style="grid-template-columns: 1.2fr 1fr">
            <div class="sale-photo">${buildingImg(u.building, u.name)}<span class="stamp">FOR SALE</span></div>
            <div class="os-card"><h2>${esc(u.name)}</h2>
                <div class="sum">
                    <div><span>Purchase price</span><span>${money(u.pricePaid)}</span></div>
                    <div><span>Upgrades</span><span>${money(u.upgradesPaid)}</span></div>
                    <div><span>Paid back</span><span>${pct(S.config.propertySellRatio)}</span></div>
                    <div class="t"><span>You get</span><span class="pos">${money(u.refund)}</span></div>
                </div>
                <div class="os-warn" style="margin-top:14px">Upgrades${lost.length ? ', ' + lost.join(' and ') : ''} are lost${lost.length ? ': sell the product first' : ''}. A running mission of this site must end first.</div>
                <div class="end"><button class="btn danger xl block" id="sellSite" ${mission ? 'disabled' : ''}>Sell property</button></div></div>
        </div>`;
    }
    function sellBind() {
        $('sellSite').onclick = async () => {
            const u = siteUnit();
            if (!await OSA.ui.confirm('Sell property', `Sell ${u.name} for ${money(u.refund)}? Its upgrades and stock are lost. This cannot be undone.`, 'Sell')) return;
            const r = await act('sell', {}, 'Property sold');
            if (r && r.ok) setTimeout(close, 1500);
        };
    }

    // ------------------------------------------------------------ weed farm
    const noActivity = text => `${head(S.unit.name)}<div class="os-empty">${esc(text)}</div>`;

    function weedPill(a) {
        if (a.paused) return pill('Stopped · upkeep unpaid', 'bad');
        if (a.mission) return pill(a.mission.label, 'warn');
        if (!a.supply) return pill('No supply', 'warn');
        return pill('Producing', 'ok');
    }
    const missionWarn = a => a.mission ? `<div class="os-warn"><b>${esc(a.mission.label)}</b> · ${dur(a.mission.left)} left${a.mission.vehicles ? ` · ${a.mission.vehicles} vehicle(s)` : ''}</div>` : '';
    const supplyLine = a => a.pendingSupply ? `+${a.pendingSupply} arriving in ${dur(a.pendingLeft)} (online time)`
        : (a.supply ? `Runs out in ${dur(a.supply * a.unitSeconds)}` : 'Empty: production stopped');

    WEED.overview = () => {
        const a = S.activity;
        if (!a) return noActivity('The farm software is not available right now.');
        const bonus = a.multiplier && a.multiplier !== 1;
        return `${banner(weedPill(a))}
        <div class="os-kpis">
            ${kpi('Supply', `${a.supply} / ${a.capacity}`, '', supplyLine(a), bar(a.supply, a.capacity, 'green'))}
            ${kpi('Product', `${a.product} / ${a.capacity}`, '', `Worth ${money(a.productValue)}`, bar(a.product, a.capacity, 'gold'))}
            ${kpi('Production', `1 / ${dur(a.unitSeconds)}`, '', 'while you are online')}
            ${kpi('Weekly bonus', bonus ? '×' + a.multiplier : '×1', bonus ? 'pos' : '', bonus ? 'on deliveries this week' : 'no bonus this week')}
        </div>
        ${missionWarn(a)}
        <div class="os-row grow c2">
            <div class="os-card"><h2>Status</h2>
                <ul class="checks">
                    <li><span>${a.paused ? '<b>Stopped</b>: the upkeep is unpaid. Deposit money in the office.'
                        : (a.supply ? `<b>Producing</b> one unit every ${dur(a.unitSeconds)} while you are online.` : '<b>No supply</b>: buy or steal supply to produce.')}</span></li>
                    <li><span>${a.pendingSupply ? `<b>${a.pendingSupply} units</b> of supply arrive in ${dur(a.pendingLeft)}.` : 'No supply order on its way.'}</span></li>
                    <li><span>${a.mission ? `<b>${esc(a.mission.label)}</b>: ${dur(a.mission.left)} left.` : (a.cooldown > 0 ? `Next mission in <b>${dur(a.cooldown)}</b>.` : 'Ready for a mission.')}</span></li>
                    <li><span>${a.product ? `<b>${a.product} units</b> ready to sell (${money(a.productValue)}).` : 'No product to sell yet.'}</span></li>
                </ul></div>
            <div class="os-card"><h2>Upgrades <small>${OSA.arr(a.upgrades).filter(u => u.owned).length} / ${OSA.arr(a.upgrades).length} installed</small></h2>
                ${OSA.arr(a.upgrades).map(u => `<div class="person"><span class="th">${img(`upgrades/${u.image || ''}.jpg`)}</span><span>${esc(u.label)}</span>
                    <small>${u.owned ? '<span class="pos">Installed</span>' : money(u.price)}</small></div>`).join('')}
                <div class="end"><button class="btn" id="toUpgrades">Open upgrades</button></div></div>
        </div>`;
    };
    WEED.overview.bind = () => {
        $('toUpgrades').onclick = () => { tab = 'upgrades'; render(); };
    };

    WEED.upgrades = () => {
        const a = S.activity;
        if (!a) return noActivity('The farm software is not available right now.');
        return `${head('Upgrades', 'Paid from the company account. Point at a card for the details.', weedPill(a))}
        <div class="ups">${OSA.arr(a.upgrades).map(u => `<div class="up">${img(`upgrades/${u.image || ''}.jpg`, u.label)}
            ${u.owned ? `<span class="pill ok badge">${icon('check')}Installed</span>` : ''}
            <div class="nm">${esc(u.label)}${u.owned ? '' : `<span>${money(u.price)}</span>`}</div>
            <div class="ov"><h3>${esc(u.label)}</h3><p>${esc(u.desc)}</p>
                <ul>${OSA.arr(u.effects).map(e => `<li>${esc(e)}</li>`).join('')}</ul>
                <div class="foot">${u.owned ? pill('Installed', 'ok', false)
                    : `<span class="price">${money(u.price)}</span><button class="btn primary xl" data-up="${esc(u.id)}" data-label="${esc(u.label)}" data-price="${u.price}">Buy upgrade</button>`}</div></div></div>`).join('')}</div>`;
    };
    WEED.upgrades.bind = () => {
        for (const b of document.querySelectorAll('[data-up]')) b.onclick = async () => {
            if (await OSA.ui.confirm('Buy upgrade', `Buy ${b.dataset.label} for ${money(b.dataset.price)} from the company account?`, 'Buy')) act('activity:upgrade', { id: b.dataset.up }, 'Upgrade installed');
        };
    };

    WEED.supply = () => {
        const a = S.activity;
        if (!a) return noActivity('The farm software is not available right now.');
        const m = a.mission;
        const big = (v, max) => `${v} <small>/ ${max}</small>`;
        return `${head('Supply / Stock', 'Supply turns into product while you are online.', weedPill(a))}
        <div class="os-kpis k2">
            ${kpi('Supply', big(a.supply, a.capacity), 'xl', supplyLine(a), bar(a.supply, a.capacity, 'green'))}
            ${kpi('Product', big(a.product, a.capacity), 'xl', `Worth ${money(a.productValue)} · one unit every ${dur(a.unitSeconds)}`, bar(a.product, a.capacity, 'gold'))}
        </div>
        ${missionWarn(a)}
        <div class="os-row grow" style="grid-template-columns: 1.3fr 1fr">
            <div class="os-card"><h2>Buy supply <small>delivered after a while</small></h2>
                <p>Costs more than stealing it, but there is no risk. One order at a time.</p>
                <div class="packs">${OSA.arr(a.packs).map(p => `<div class="pack"><div><b>${p.units} units</b><small>arrives in ${dur(p.seconds)} (online time)</small></div>
                    <button class="btn primary" data-pack="${esc(p.id)}" ${a.pendingSupply || m ? 'disabled' : ''}>${money(p.price)}</button></div>`).join('')}</div>
                ${a.pendingSupply ? `<div class="end"><div class="os-note">An order of ${a.pendingSupply} units is on its way: ${dur(a.pendingLeft)} left.</div></div>` : ''}</div>
            <div class="os-card"><h2>Steal supply <small>free</small></h2>
                <p>Take a shipment from armed guards and drive it back to the farm. ${a.stealUnits[0]}–${a.stealUnits[1]} units.</p>
                <ul class="checks"><li><span><b>Armed guards</b> at the pick-up point</span></li><li><span>Associates can help you</span></li>
                    <li><span>${a.cooldown > 0 ? `Next mission in <b>${dur(a.cooldown)}</b>` : 'Ready to start'}</span></li></ul>
                <div class="end"><button class="btn primary xl block" id="stealBtn" ${m ? 'disabled' : ''}>Start mission</button></div></div>
        </div>`;
    };
    WEED.supply.bind = () => {
        for (const b of document.querySelectorAll('[data-pack]')) b.onclick = () => act('activity:buy', { pack: b.dataset.pack }, 'Supply ordered');
        $('stealBtn').onclick = () => act('activity:steal', {}, 'Mission started').then(r => { if (r && r.ok) close(); });
    };

    let sellAmount = 0;
    WEED.sales = () => {
        const a = S.activity;
        if (!a) return noActivity('The farm software is not available right now.');
        const bonus = a.multiplier && a.multiplier !== 1;
        const vans = Math.round(a.maxSell / a.perVehicle);
        const options = [];
        for (let n = a.perVehicle; n <= a.maxSell; n += a.perVehicle) options.push(n);
        const share = pct(S.config.associateShare);
        return `${head('Sales', `Deliver product to buyers. ${a.perVehicle} units per van.`, bonus ? pill(`Weekly bonus · sales ×${a.multiplier}`, 'info', false) : weedPill(a))}
        <div class="os-kpis k3">
            ${kpi('Product', `${a.product} units`, '', `worth ${money(a.productValue)}${bonus ? ' before the bonus' : ''}`)}
            ${kpi('Vans available', String(vans), '', `1 + ${a.associates} associate(s) online`)}
            ${kpi('Associate share', share, '', 'an associate keeps of their van')}
        </div>
        ${missionWarn(a)}
        <div class="os-row grow" style="grid-template-columns: 1.4fr 1fr">
            <div class="os-card"><h2>How much to sell</h2>
                <div class="choice" id="sellSeg">${options.map(n => {
                    const units = Math.min(n, a.product), v = n / a.perVehicle;
                    const ok = a.product > n - a.perVehicle;
                    return `<button data-n="${n}" ${ok ? '' : 'disabled'}><b>${ok ? units : n}</b><span>${v} van${v > 1 ? 's' : ''} · ${ok ? `${v} buyer${v > 1 ? 's' : ''}` : 'not enough product'}</span></button>`;
                }).join('')}</div>
                <div id="sellWarn" style="margin-top:16px"></div>
                <div class="end"><button class="btn danger xl block" id="sellStart" ${a.mission || !a.product ? 'disabled' : ''}>Start delivery</button></div></div>
            <div class="os-card"><h2>Before you start</h2>
                <ul class="checks">
                    <li><span>Every van goes to a <b>different buyer</b> and needs its own driver.</span></li>
                    <li><span>You have <b>30 minutes</b>; undelivered cargo is lost.</span></li>
                    <li><span>Half of the deliveries meet <b>enemies</b> on the way.</span></li>
                    <li><span>Nearby players see the van on their map.</span></li>
                    <li><span>If you disconnect, half of the cargo returns to the farm.</span></li>
                </ul></div>
        </div>`;
    };
    WEED.sales.bind = () => {
        const a = S.activity;
        if (!a) return;
        const seg = $('sellSeg');
        const maxSell = Math.min(a.product, a.maxSell);
        if (!sellAmount || sellAmount > maxSell + a.perVehicle - 1) sellAmount = maxSell ? a.perVehicle : 0;
        const paint = () => {
            for (const b of seg.querySelectorAll('button')) b.classList.toggle('on', Number(b.dataset.n) === sellAmount);
            const units = Math.min(sellAmount, a.product);
            const vehicles = Math.ceil(units / a.perVehicle);
            $('sellWarn').innerHTML = vehicles > 1
                ? `<div class="os-warn">${units} units need <b>${vehicles} vans</b>. Each one goes to a different buyer and needs its own driver. Undelivered cargo is lost after <b>30 minutes</b>.</div>`
                : (units ? `<div class="os-note">${units} units in one van. Deliver within 30 minutes or the cargo is lost.</div>` : '');
        };
        for (const b of seg.querySelectorAll('button')) b.onclick = () => { sellAmount = Number(b.dataset.n); paint(); };
        paint();
        $('sellStart').onclick = async () => {
            const units = Math.min(sellAmount, a.product);
            if (!units) return;
            const vehicles = Math.ceil(units / a.perVehicle);
            if (vehicles > 1 && !await OSA.ui.confirm('Start delivery', `${vehicles} vans, ${vehicles} different buyers, 30 minutes. Every van needs a driver. Start?`, 'Start')) return;
            const r = await act('activity:sell', { amount: units }, 'Delivery started');
            if (r && r.ok) close();
        };
    };

    WEED.sell = sellView;
    WEED.sell.bind = sellBind;

    // ------------------------------------------------------------ casino
    const casinoPill = a => a.paused ? pill('Closed · upkeep unpaid', 'bad') : pill('Open', 'ok');

    CASINO.overview = () => {
        const a = S.activity;
        if (!a) return noActivity('The casino software is not available right now.');
        const hours = OSA.arr(a.hours).slice(-24);
        const max = Math.max(1, ...hours.map(h => Math.abs(h.result)));
        return `${banner(casinoPill(a))}
        <div class="os-kpis k3">
            ${kpi('Next result in', dur(a.hourLeft), '', 'online time')}
            ${kpi('Average · last 24 h', signed(a.average), a.average >= 0 ? 'pos' : 'neg', 'per hour, before upkeep')}
            ${kpi('Laundering queue', money(a.launderQueue), 'dirty', `max ${money(a.launderPerHour)} / hour · fee ${pct(a.launderFee)}`)}
        </div>
        ${a.paused ? '<div class="os-warn">The casino is closed: pay the upkeep (deposit money in the office) to open it again.</div>' : ''}
        <div class="os-card grow"><h2>Hourly results <small>${hours.length ? 'last ' + hours.length + ' hours' : ''}</small></h2>
            ${hours.length ? `<div class="chart">${hours.map(h => `<div class="${h.result < 0 ? 'n' : (h.event ? 'e' : '')}" style="height:${Math.max(2, Math.round(Math.abs(h.result) / max * 100))}%" title="${stamp(h.ts)}: ${money(h.result)}${h.event ? ' · ' + esc(h.event) : ''}"></div>`).join('')}</div>
                <div class="axis"><span>${stamp(hours[0].ts)}</span><span>now</span></div>`
                : '<div class="os-empty">No results yet: the casino works while you are online.</div>'}</div>`;
    };

    CASINO.launder = () => {
        const a = S.activity;
        if (!a) return noActivity('The casino software is not available right now.');
        const hours = OSA.arr(a.hours).slice(-6).reverse();
        return `${head('Laundering', `Dirty money in the queue is cleaned with every casino hour.`, casinoPill(a))}
        <div class="os-kpis k3">
            ${kpi('Unlaundered (dirty)', money(S.company.dirty), 'dirty', 'on the company account')}
            ${kpi('In the queue', money(a.launderQueue), 'dirty', a.launderQueue ? `about ${Math.ceil(a.launderQueue / a.launderPerHour)} casino hour(s)` : 'empty')}
            ${kpi('Per hour', money(a.launderPerHour), '', `fee ${pct(a.launderFee)}`)}
        </div>
        <div class="os-row grow" style="grid-template-columns: 1fr 1fr">
            <div class="os-card"><h2>Add to the queue</h2>
                <p>Up to ${money(a.launderPerHour)} is cleaned every casino hour; the casino keeps ${pct(a.launderFee)}.</p>
                <div class="os-flex"><input class="input" id="launderAmount" type="number" min="1" placeholder="Amount" style="width:220px">
                <button class="btn primary" id="launderBtn">Add to queue</button>
                <button class="btn" id="launderAll">Queue all</button></div>
                ${a.launderQueue ? '<div class="end"><button class="btn danger" id="launderClear">Clear queue</button></div>' : ''}</div>
            <div class="os-card"><h2>Recent hours</h2>
                ${hours.length ? `<table class="os-table"><tr><th>Hour</th><th>Event</th><th class="num">Result</th></tr>${hours.map(h => `<tr><td>${stamp(h.ts)}</td><td>${esc(h.event || '–')}</td><td class="num ${h.result < 0 ? 'neg' : 'pos'}">${signed(h.result)}</td></tr>`).join('')}</table>`
                    : '<div class="os-empty">No results yet.</div>'}</div>
        </div>`;
    };
    CASINO.launder.bind = () => {
        if (!S.activity) return;
        $('launderBtn').onclick = () => act('activity:launder', { amount: Number($('launderAmount').value) }, 'Queued').then(r => { if (r && r.ok) $('launderAmount').value = ''; });
        $('launderAll').onclick = () => act('activity:launder', { amount: S.company.dirty - S.activity.launderQueue }, 'Queued');
        if ($('launderClear')) $('launderClear').onclick = () => act('activity:clear', {}, 'Queue cleared');
    };

    CASINO.sell = sellView;
    CASINO.sell.bind = sellBind;

    VIEWS.office = OFFICE;
    VIEWS.weed = WEED;
    VIEWS.casino = CASINO;

    // ------------------------------------------------------------ render / refresh
    function render() {
        if (!S) return;
        const views = VIEWS[kind()] || OFFICE;
        if (!views[tab]) tab = 'overview';
        nav();
        $('osPlace').textContent = S.unit.name + (kind() === 'office' && S.unit.id === S.company.hqUnit ? ' · Headquarters' : '');
        const view = views[tab];
        const html = view();
        if (html === lastHtml) return;   // unchanged: keeps hover states and the open select
        lastHtml = html;
        keepInputs(() => {
            $('view').innerHTML = html;
            if (view.bind) view.bind();
        });
    }
    let lastHtml = '';

    async function refresh() {
        let r;
        try { r = await api.call('pcState', UNIT); } catch (e) { r = null; }
        if (!r || !r.ok) {
            $('view').innerHTML = `<div class="os-empty">${esc(errText(r))}</div>`;
            return;
        }
        S = r;
        render();
    }

    refresh();
    setInterval(() => { if (!busy && !document.querySelector('.osa-modal-back:not([hidden])')) refresh(); }, 5000);
    addEventListener('resize', () => { if (S && tab === 'overview' && kind() === 'office') { lastHtml = ''; render(); } });
})();
