// OrgOS - the organization computer. One page, several apps (sidebar). The
// state comes from biz_pc:pcState(unit) every few seconds; actions go through
// biz_pc:pcAction(unit, action, args).
(function () {
    'use strict';
    const api = OSA.api();
    const esc = OSA.esc;
    const $ = id => document.getElementById(id);
    const q = new URLSearchParams(location.search);
    const UNIT = Number(q.get('unit')) || 0;

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
        mission_running: 'A mission of this property is already running.',
        mission_cooldown: 'Wait a little before the next mission.',
        no_product: 'There is no product to sell.', no_space: 'There is no room for more supply.',
        not_enough_product: 'Not enough product.', too_many: 'That is more than you can deliver now.',
        paused: 'The business is stopped: pay the upkeep first (deposit money).',
        no_casino: 'Laundering needs a casino.', pending: 'An order is already on its way.',
        unknown_upgrade: 'Unknown upgrade.', in_vehicle: 'Get out of the vehicle first.',
    };
    const errText = r => (r && ERRORS[r.error]) || (r && r.error ? 'Failed: ' + r.error : 'Something went wrong.');
    const money = n => (n < 0 ? '−€ ' : '€ ') + Math.abs(Math.round(Number(n) || 0)).toLocaleString('en-US');
    const signed = n => (n > 0 ? '+' : '') + money(n);
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
    const CAT = {
        'property.buy': 'Property', 'property.sell': 'Property', 'property.refund': 'Property', 'property.upgrade': 'Upgrade',
        'weed.sale': 'Weed · sale', 'weed.supply': 'Weed · supply', 'casino.hour': 'Casino', launder: 'Laundering',
        upkeep: 'Upkeep', deposit: 'Deposit', withdrawal: 'Withdrawal', rename: 'Rename', founded: 'Founded',
        'admin.adjust': 'Admin', 'admin.rename': 'Admin', 'company.sell': 'Sale',
    };

    let S = null;          // last state
    let tab = 'overview';
    let busy = false;

    // ------------------------------------------------------------ frame
    function close() {
        if (window.mta && mta.triggerEvent) mta.triggerEvent('bizpc:pageClose');
        api.call('pcClose').catch(() => {});
    }
    $('closeBtn').addEventListener('click', close);
    document.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
    setInterval(() => { $('clock').textContent = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); }, 1000);

    function apps() {
        const list = [];
        const kind = S && S.unit ? S.unit.kind : '';
        if (kind === 'weed') list.push(['weed', 'Weed farm']);
        if (kind === 'casino') list.push(['casino', 'Casino']);
        if (list.length) list.push(['sep']);
        list.push(['overview', 'Overview'], ['finance', 'Finance'], ['properties', 'Properties'], ['settings', 'Settings']);
        return list;
    }

    function nav() {
        $('nav').innerHTML = apps().map(([id, label]) => id === 'sep' ? '<div class="sep"></div>'
            : `<a data-tab="${id}" class="${id === tab ? 'on' : ''}">${esc(label)}</a>`).join('');
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
        fn();
        for (const id in vals) { const el = $(id); if (el) el.value = vals[id]; }
        if (focus && $(focus)) $(focus).focus();
    }

    function kpi(k, v, cls, sub) {
        return `<div class="os-kpi"><div class="k">${esc(k)}</div><div class="v ${cls || ''}">${v}</div>${sub ? `<div class="s">${sub}</div>` : ''}</div>`;
    }

    function ledgerTable(rows) {
        rows = OSA.arr(rows);
        if (!rows.length) return '<div class="os-empty">No transactions yet.</div>';
        return `<table class="os-table"><tr><th>Date</th><th>Category</th><th>Description</th><th class="num">Amount</th><th class="num">Balance</th></tr>` +
            rows.map(r => `<tr><td>${stamp(r.ts)}</td><td>${esc(CAT[r.category] || r.category)}${r.dirty ? '<span class="os-tag">dirty</span>' : ''}</td>
                <td>${esc(r.description)}</td><td class="num ${r.amount > 0 ? 'pos' : (r.amount < 0 ? 'neg' : '')}">${r.amount ? signed(r.amount) : '–'}</td>
                <td class="num">${money(r.balance)}</td></tr>`).join('') + '</table>';
    }

    // ------------------------------------------------------------ apps
    const VIEWS = {};

    VIEWS.overview = () => {
        const c = S.company;
        return `<div class="os-kpis">
            ${kpi('Balance', money(c.balance), '', `clean ${money(c.clean)} · <span class="dirty">dirty ${money(c.dirty)}</span>`)}
            ${kpi('Income · 7 days', signed(S.income7), 'pos')}
            ${kpi('Expenses · 7 days', money(-S.expenses7), 'neg')}
            ${kpi('Company value', money(c.value), '', `sale now: ${money(c.salePayout)}`)}
        </div>
        ${c.paused ? `<div class="os-warn">The upkeep could not be paid: production and the casino are stopped until the company account covers ${money(c.upkeepAmount)}.</div>` : ''}
        <div class="os-grid2">
            <div class="os-card"><h2>Upkeep</h2>
                <p>Every property and the office cost ${money(c.upkeepAmount)} every 2 hours of your online time.</p>
                <div class="os-row"><b>Next payment in ${dur(c.upkeepIn)}</b> <span class="osa-muted">(online time)</span></div></div>
            <div class="os-card"><h2>Associates</h2>
                <p>${OSA.arr(c.associates).length} / ${c.maxAssociates} online. Invite helpers with the Organization app on your phone; they stay until they leave or disconnect.</p>
                ${OSA.arr(c.associates).map(a => `<div>· ${esc(OSA.clean(a.name))}</div>`).join('')}</div>
        </div>
        <div class="os-card"><h2>Latest transactions</h2>${ledgerTable(OSA.arr(S.ledger).slice(0, 8))}</div>`;
    };

    VIEWS.finance = () => {
        const c = S.company;
        return `<div class="os-kpis">
            ${kpi('Clean balance', money(c.clean))}
            ${kpi('Unlaundered (dirty)', money(c.dirty), 'dirty', c.launder ? `${money(c.launder)} waiting for laundering` : '')}
            ${kpi('Your bank account', money(S.bank))}
        </div>
        <div class="os-grid2">
            <div class="os-card"><h2>Deposit</h2><p>From your bank account to the company account.</p>
                <div class="os-row"><input class="osa-input" id="depAmount" type="number" min="1" placeholder="Amount">
                <button class="osa-btn primary" id="depBtn">Deposit</button></div></div>
            <div class="os-card"><h2>Withdraw</h2><p>From the company account to your bank account.</p>
                <div class="os-row"><input class="osa-input" id="wdAmount" type="number" min="1" placeholder="Amount">
                <select class="osa-select" id="wdPart"><option value="clean">Clean money</option><option value="dirty">Dirty money</option></select>
                <button class="osa-btn primary" id="wdBtn">Withdraw</button></div>
                <div class="os-note">Dirty money can be withdrawn, but unlaundered money may have consequences later. Launder it in a casino first.</div></div>
        </div>
        <div class="os-card"><h2>Ledger</h2>
            <div class="os-row" style="margin-bottom:8px"><select class="osa-select" id="ledFilter">
                <option value="">All categories</option><option value="weed">Weed</option><option value="casino">Casino</option>
                <option value="launder">Laundering</option><option value="upkeep">Upkeep</option><option value="property">Properties</option>
                <option value="deposit">Deposits</option><option value="withdrawal">Withdrawals</option></select></div>
            <div id="ledger">${ledgerTable(S.ledger)}</div></div>`;
    };
    VIEWS.finance.bind = () => {
        $('depBtn').onclick = () => act('deposit', { amount: Number($('depAmount').value) }, 'Deposited').then(r => { if (r && r.ok) $('depAmount').value = ''; });
        $('wdBtn').onclick = () => act('withdraw', { amount: Number($('wdAmount').value), part: $('wdPart').value }, 'Withdrawn').then(r => { if (r && r.ok) $('wdAmount').value = ''; });
        $('ledFilter').onchange = async () => {
            let r;
            try { r = await api.call('pcAction', UNIT, 'ledger', { category: $('ledFilter').value }); } catch (e) { r = null; }
            $('ledger').innerHTML = r && r.ok ? ledgerTable(r.rows) : esc(errText(r));
        };
    };

    VIEWS.properties = () => {
        const c = S.company;
        const owned = OSA.arr(c.units);
        const ownedIds = new Set(owned.map(u => u.propertyId));
        const buyable = OSA.arr(S.catalog).filter(p => p.kind !== 'office' && !ownedIds.has(p.id));
        return `<div class="os-card"><h2>Your properties</h2>
            ${owned.map(u => `<div class="os-prop"><div><b>${esc(u.name)}${u.id === c.hqUnit ? ' · headquarters' : ''}</b>
                <small>${esc(u.kind)} · paid ${money(u.pricePaid)}${u.upgradesPaid ? ' + upgrades ' + money(u.upgradesPaid) : ''} · upkeep ${money(u.upkeep)} / 2 h${u.stockValue ? ' · stock ' + money(u.stockValue) : ''}</small></div>
                ${u.id === c.hqUnit ? '<span class="osa-muted">Move it on sabusinessregistry.eu</span>'
                    : `<button class="osa-btn danger small" data-sell="${u.id}" data-name="${esc(u.name)}" data-refund="${u.refund}">Sell (${money(u.refund)})</button>`}</div>`).join('')}
        </div>
        <div class="os-card"><h2>Available properties</h2>
            ${buyable.length ? buyable.map(p => `<div class="os-prop"><div><b>${esc(p.name)}</b>
                <small>${esc(p.city || '')} · ${esc(p.kind)}${p.illegal ? ' · illegal' : ''} · upkeep ${money(p.upkeep)} / 2 h</small></div>
                <button class="osa-btn primary small" data-buy="${esc(p.id)}" data-name="${esc(p.name)}" data-price="${p.price}">Buy ${money(p.price)}</button></div>`).join('')
                : '<div class="os-empty">You own every available property.</div>'}
        </div>`;
    };
    VIEWS.properties.bind = () => {
        for (const b of document.querySelectorAll('[data-buy]')) b.onclick = async () => {
            if (await OSA.ui.confirm('Buy property', `Buy ${b.dataset.name} for ${money(b.dataset.price)} from the company account?`, 'Buy'))
                act('buy', { propertyId: b.dataset.buy }, 'Purchase started');
        };
        for (const b of document.querySelectorAll('[data-sell]')) b.onclick = async () => {
            if (await OSA.ui.confirm('Sell property', `Sell ${b.dataset.name} for ${money(b.dataset.refund)}? Its stock and upgrades are lost.`, 'Sell'))
                act('sell', { unitId: Number(b.dataset.sell) }, 'Sold');
        };
    };

    VIEWS.settings = () => {
        const c = S.company;
        const wait = c.renameWait > 0 ? `<p>Next rename possible in ${dur(c.renameWait)}.</p>` : '';
        return `<div class="os-grid2">
            <div class="os-card"><h2>Name</h2><p>Renaming costs ${money(c.renameCost)} from the company account.</p>${wait}
                <div class="os-row"><input class="osa-input" id="newName" maxlength="32" placeholder="${esc(c.name)}" style="width:260px">
                <button class="osa-btn primary" id="renameBtn">Rename</button></div></div>
            <div class="os-card"><h2>Headquarters</h2><p>Move your headquarters on sabusinessregistry.eu (in-game browser).</p></div>
        </div>
        <div class="os-card"><h2>Sell the organization</h2>
            <p>The organization ends. You get the full balance (${money(c.balance)}) and ${Math.round(S.config.saleRatio * 100)}% of the properties, upgrades and stock (${money(c.assets)}).</p>
            <div class="os-row"><b>Payout now: ${money(c.salePayout)}</b></div>
            <div class="os-row" style="margin-top:10px"><input class="osa-input" id="sellConfirm" placeholder="Type the organization name" style="width:260px">
            <button class="osa-btn danger" id="sellBtn">Sell organization</button></div></div>`;
    };
    VIEWS.settings.bind = () => {
        $('renameBtn').onclick = () => act('rename', { name: $('newName').value.trim() }, 'Renaming…');
        $('sellBtn').onclick = async () => {
            const name = $('sellConfirm').value.trim();
            if (name !== S.company.name) return OSA.toast(ERRORS.confirm_mismatch, false);
            if (!await OSA.ui.confirm('Sell organization', `Sell ${S.company.name} for ${money(S.company.salePayout)}? This cannot be undone.`, 'Sell')) return;
            const r = await act('sellorg', { confirm: name }, 'Organization sold');
            if (r && r.ok) setTimeout(close, 1500);
        };
    };

    // ------------------------------------------------------------ weed farm
    VIEWS.weed = () => {
        const a = S.activity;
        if (!a) return '<div class="os-empty">The farm software is not available right now.</div>';
        const pctS = a.capacity ? Math.round(a.supply / a.capacity * 100) : 0;
        const pctP = a.capacity ? Math.round(a.product / a.capacity * 100) : 0;
        const m = a.mission;
        const mult = a.multiplier && a.multiplier !== 1 ? `<span class="osa-pill ok">Weekly bonus: sales ×${a.multiplier}</span>` : '';
        const maxSell = Math.min(a.product, a.maxSell);
        const options = [];
        for (let n = a.perVehicle; n <= a.maxSell; n += a.perVehicle) options.push(n);
        return `<div class="os-grid2">
            <div class="os-kpi"><div class="k">Supply</div><div class="v">${a.supply} / ${a.capacity}</div><div class="os-bar green"><i style="width:${pctS}%"></i></div>
                <div class="s">${a.pendingSupply ? `+${a.pendingSupply} arriving in ${dur(a.pendingLeft)} (online time)` : (a.supply ? `Runs out in ${dur(a.supply * a.unitSeconds)}` : 'Empty: production stopped')}</div></div>
            <div class="os-kpi"><div class="k">Product</div><div class="v">${a.product} / ${a.capacity}</div><div class="os-bar gold"><i style="width:${pctP}%"></i></div>
                <div class="s">Worth ${money(a.productValue)} · one unit every ${dur(a.unitSeconds)}${a.paused ? ' · <span class="neg">stopped (upkeep)</span>' : ''}</div></div>
        </div>
        <div class="os-row" style="margin:12px 0">${mult}</div>
        ${m ? `<div class="os-warn"><b>${esc(m.label)}</b> · ${dur(m.left)} left${m.vehicles ? ` · ${m.vehicles} vehicle(s)` : ''}</div>` : ''}
        <div class="os-grid3">
            <div class="os-card"><h2>Buy supply</h2><p>Delivered to the farm after a while (online time). Costs more than stealing it.</p>
                ${OSA.arr(a.packs).map(p => `<div class="os-row" style="margin-bottom:6px"><button class="osa-btn small" data-pack="${esc(p.id)}" ${a.pendingSupply || m ? 'disabled' : ''}>${p.units} units · ${money(p.price)}</button>
                    <span class="osa-muted">${dur(p.seconds)}</span></div>`).join('')}</div>
            <div class="os-card"><h2>Steal supply</h2><p>Take a shipment from armed guards and bring it here. ${a.stealUnits[0]}–${a.stealUnits[1]} units, free.</p>
                <button class="osa-btn primary" id="stealBtn" ${m ? 'disabled' : ''}>Start mission</button>
                ${a.cooldown > 0 ? `<div class="os-note">Next mission in ${dur(a.cooldown)}</div>` : ''}</div>
            <div class="os-card"><h2>Sell product</h2>
                <p>${a.perVehicle} units per vehicle. Every associate online adds a vehicle (${a.associates} online). ${Math.round(S.config.associateShare * 100)}% of an associate's delivery goes to him.</p>
                <div class="os-seg" id="sellSeg">${options.map(n => `<button data-n="${n}" ${n > maxSell + a.perVehicle - 1 ? 'disabled' : ''}>${n}</button>`).join('')}</div>
                <div id="sellWarn"></div>
                <div class="os-row" style="margin-top:10px"><button class="osa-btn danger" id="sellStart" ${m || !a.product ? 'disabled' : ''}>Start delivery</button></div></div>
        </div>
        <div class="os-card"><h2>Upgrades</h2>
            ${OSA.arr(a.upgrades).map(u => `<div class="os-prop"><div><b>${esc(u.label)}</b><small>${esc(u.desc)}</small></div>
                ${u.owned ? '<span class="osa-pill ok">Installed</span>' : `<button class="osa-btn primary small" data-up="${esc(u.id)}" data-label="${esc(u.label)}" data-price="${u.price}">Buy ${money(u.price)}</button>`}</div>`).join('')}
        </div>`;
    };
    let sellAmount = 0;
    VIEWS.weed.bind = () => {
        const a = S.activity;
        if (!a) return;
        for (const b of document.querySelectorAll('[data-pack]')) b.onclick = () => act('activity:buy', { pack: b.dataset.pack }, 'Supply ordered');
        for (const b of document.querySelectorAll('[data-up]')) b.onclick = async () => {
            if (await OSA.ui.confirm('Buy upgrade', `Buy ${b.dataset.label} for ${money(b.dataset.price)}?`, 'Buy')) act('activity:upgrade', { id: b.dataset.up }, 'Upgrade installed');
        };
        if ($('stealBtn')) $('stealBtn').onclick = () => act('activity:steal', {}, 'Mission started').then(r => { if (r && r.ok) close(); });
        const seg = $('sellSeg');
        const maxSell = Math.min(a.product, a.maxSell);
        if (!sellAmount || sellAmount > maxSell + a.perVehicle - 1) sellAmount = Math.min(a.perVehicle, maxSell) ? a.perVehicle : 0;
        const paint = () => {
            for (const b of seg.querySelectorAll('button')) b.classList.toggle('on', Number(b.dataset.n) === sellAmount);
            const units = Math.min(sellAmount, a.product);
            const vehicles = Math.ceil(units / a.perVehicle);
            $('sellWarn').innerHTML = vehicles > 1
                ? `<div class="os-warn">${units} units need <b>${vehicles} vehicles</b>. Each one goes to a different buyer and needs its own driver. Undelivered cargo is lost after <b>30 minutes</b>.</div>`
                : (units ? `<div class="os-note">${units} units in one vehicle. Deliver within 30 minutes or the cargo is lost.</div>` : '');
        };
        for (const b of seg.querySelectorAll('button')) b.onclick = () => { sellAmount = Number(b.dataset.n); paint(); };
        paint();
        $('sellStart').onclick = async () => {
            const units = Math.min(sellAmount, a.product);
            if (!units) return;
            const vehicles = Math.ceil(units / a.perVehicle);
            if (vehicles > 1 && !await OSA.ui.confirm('Start delivery', `${vehicles} vehicles, ${vehicles} different buyers, 30 minutes. Every vehicle needs a driver. Start?`, 'Start')) return;
            const r = await act('activity:sell', { amount: units }, 'Delivery started');
            if (r && r.ok) close();
        };
    };

    // ------------------------------------------------------------ casino
    VIEWS.casino = () => {
        const a = S.activity;
        if (!a) return '<div class="os-empty">The casino software is not available right now.</div>';
        const hours = OSA.arr(a.hours).slice(-24);
        const max = Math.max(1, ...hours.map(h => Math.abs(h.result)));
        return `<div class="os-kpis">
            ${kpi('Next result in', dur(a.hourLeft), '', 'online time')}
            ${kpi('Average · last 24 h', money(a.average), a.average >= 0 ? 'pos' : 'neg', 'before upkeep')}
            ${kpi('Waiting for laundering', money(a.launderQueue), 'dirty', `max ${money(a.launderPerHour)} / hour · fee ${Math.round(a.launderFee * 100)}%`)}
        </div>
        ${a.paused ? '<div class="os-warn">The casino is closed: pay the upkeep (deposit money) to open it again.</div>' : ''}
        <div class="os-card"><h2>Hourly results</h2>
            ${hours.length ? `<div class="os-chart">${hours.map(h => `<div class="${h.result < 0 ? 'n' : (h.event ? 'e' : '')}" style="height:${Math.max(2, Math.round(Math.abs(h.result) / max * 100))}%" title="${stamp(h.ts)}: ${money(h.result)}${h.event ? ' · ' + esc(h.event) : ''}"></div>`).join('')}</div>` : '<div class="os-empty">No results yet: the casino works while you are online.</div>'}
            ${hours.length ? `<table class="os-table" style="margin-top:12px"><tr><th>Hour</th><th>Event</th><th class="num">Result</th></tr>${hours.slice(-6).reverse().map(h => `<tr><td>${stamp(h.ts)}</td><td>${esc(h.event || '–')}</td><td class="num ${h.result < 0 ? 'neg' : 'pos'}">${signed(h.result)}</td></tr>`).join('')}</table>` : ''}
        </div>
        <div class="os-card"><h2>Launder money</h2>
            <p>Dirty money put in the queue is cleaned with every casino hour (up to ${money(a.launderPerHour)}, ${Math.round(a.launderFee * 100)}% fee). Unlaundered: ${money(S.company.dirty)}.</p>
            <div class="os-row"><input class="osa-input" id="launderAmount" type="number" min="1" placeholder="Amount">
            <button class="osa-btn primary" id="launderBtn">Add to queue</button>
            <button class="osa-btn" id="launderAll">Queue all</button>
            ${a.launderQueue ? '<button class="osa-btn danger" id="launderClear">Clear queue</button>' : ''}</div></div>`;
    };
    VIEWS.casino.bind = () => {
        if (!S.activity) return;
        $('launderBtn').onclick = () => act('activity:launder', { amount: Number($('launderAmount').value) }, 'Queued').then(r => { if (r && r.ok) $('launderAmount').value = ''; });
        $('launderAll').onclick = () => act('activity:launder', { amount: S.company.dirty - S.activity.launderQueue }, 'Queued');
        if ($('launderClear')) $('launderClear').onclick = () => act('activity:clear', {}, 'Queue cleared');
    };

    // ------------------------------------------------------------ render / refresh
    function render() {
        if (!S) return;
        nav();
        const titles = { overview: S.company.name, finance: 'Finance', properties: 'Properties', settings: 'Settings', weed: S.unit.name, casino: S.unit.name };
        if (!VIEWS[tab]) tab = 'overview';
        $('title').textContent = titles[tab] || '';
        $('osPlace').textContent = S.unit.name;
        const pill = $('statePill');
        pill.textContent = S.company.paused ? 'Stopped · upkeep unpaid' : 'Running';
        pill.className = 'osa-pill ' + (S.company.paused ? 'bad' : 'ok');
        keepInputs(() => {
            $('view').innerHTML = VIEWS[tab]();
            if (VIEWS[tab].bind) VIEWS[tab].bind();
        });
    }

    async function refresh() {
        let r;
        try { r = await api.call('pcState', UNIT); } catch (e) { r = null; }
        if (!r || !r.ok) {
            $('view').innerHTML = `<div class="os-empty">${esc(errText(r))}</div>`;
            return;
        }
        const first = !S;
        S = r;
        if (first && (S.unit.kind === 'weed' || S.unit.kind === 'casino')) tab = S.unit.kind;
        render();
    }

    refresh();
    setInterval(() => { if (!busy && !document.querySelector('.osa-modal-back:not([hidden])')) refresh(); }, 5000);
})();
