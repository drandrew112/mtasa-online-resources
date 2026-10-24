// sabusinessregistry.eu - register / move headquarters, registry search, top list.
// Every call goes to biz_web's server exports (in-game only).
(function () {
    'use strict';
    const api = OSA.api();
    const esc = OSA.esc;
    const $ = id => document.getElementById(id);

    const ERRORS = {
        ingame_only: 'This service is only available in game.',
        not_logged_in: 'Log in to register an organization.',
        unavailable: 'The registry is not available right now. Try again later.',
        has_company: 'You already have an organization.',
        name_short: 'The name is too short.',
        name_long: 'The name is too long.',
        name_invalid: 'The name contains characters that are not allowed.',
        name_taken: 'That name is already taken.',
        bad_office: 'Choose a headquarters on the map.',
        not_enough_money: 'You do not have enough money for this.',
        no_company: 'You have no organization.',
        already_owned: 'That is already your headquarters.',
    };
    const errText = r => (r && ERRORS[r.error]) || 'Something went wrong. Try again.';
    const money = n => '€ ' + Math.round(Number(n) || 0).toLocaleString('en-US');
    const date = ts => ts ? new Date(ts * 1000).toLocaleDateString('en-GB', { year: 'numeric', month: 'short', day: 'numeric' }) : '–';
    const ACT = { weed: 'Weed', casino: 'Casino' };
    const tags = list => (OSA.arr(list).map(a => `<span class="br-tag ${esc(a)}">${esc(ACT[a] || a)}</span>`).join('')) || '<span class="br-small">–</span>';

    let state = null;
    let selected = null;      // office id (register)
    let moveTo = null;        // office id (move)
    let map = null, map2 = null;
    let pendingPoll = null;

    function msg(el, text, ok) {
        el.textContent = text || '';
        el.className = 'br-msg' + (text ? (ok ? ' ok' : ' bad') : '');
    }

    // ------------------------------------------------------------ tabs
    function show(tab) {
        for (const a of document.querySelectorAll('#nav a')) a.classList.toggle('on', a.dataset.tab === tab);
        for (const p of document.querySelectorAll('.br-page')) p.hidden = p.id !== 'page-' + tab;
        if (tab === 'registry') loadRegistry();
        if (tab === 'top') loadTop();
        if (tab === 'register') { if (map) map.fit(); if (map2) map2.fit(); }
    }
    for (const a of document.querySelectorAll('#nav a')) a.addEventListener('click', () => show(a.dataset.tab));

    // ------------------------------------------------------------ building photos (biz_core/img/buildings)
    // a missing picture hides itself and leaves the tinted frame
    const photo = (building, alt) => building
        ? `<img src="/biz_core/img/buildings/${esc(building)}.jpg" alt="${esc(alt || '')}" onerror="this.classList.add('noimg')">` : '';
    const tierName = o => o.tier ? o.tier[0].toUpperCase() + o.tier.slice(1) : '';

    function setPhoto(el, o, sub) {
        el.hidden = !o;
        if (o) el.innerHTML = `${photo(o.building, o.name)}<div class="cap"><b>${esc(o.name)}</b><small>${esc(sub)}</small></div>`;
    }

    // ------------------------------------------------------------ office lists + maps
    function officeRow(o, on, cur) {
        return `<div class="br-office${on ? ' on' : ''}${cur ? ' cur' : ''}" data-id="${esc(o.id)}">
            <span class="th">${photo(o.building)}</span>
            <b>${esc(o.name)}</b><span class="p">${cur ? 'current' : money((o.gross ?? o.price))}</span>
            <small>${esc(o.city || '')} · ${esc(tierName(o))} · upkeep ${money(o.upkeep)} / 2 h online</small></div>`;
    }

    function drawPins(m, prefix, current, chosen, onPick) {
        const keep = new Set();
        for (const o of state.offices) {
            const key = prefix + o.id;
            keep.add(key);
            const cls = 'br-pin' + (o.id === chosen ? ' on' : '') + (o.id === current ? ' cur' : '');
            m.marker(key, o.x, o.y, cls, o.id === chosen ? `<span class="lbl">${esc(o.name)}</span>` : '', () => onPick(o.id));
        }
        m.removeMissing(prefix, keep);
    }

    function renderRegister() {
        const list = $('officeList');
        list.innerHTML = state.offices.map(o => officeRow(o, o.id === selected)).join('');
        for (const el of list.querySelectorAll('.br-office')) el.addEventListener('click', () => pick(el.dataset.id));
        if (!map) map = new OSA.Map($('map'), { maxZoom: 3 });
        drawPins(map, 'o:', null, selected, pick);

        const o = state.offices.find(x => x.id === selected);
        setPhoto($('pickPhoto'), o, o ? `${o.city || ''} · ${tierName(o)} office` : '');
        $('sumFee').textContent = money(state.regFee);
        $('sumOfficeLabel').textContent = o ? 'Headquarters: ' + o.name : 'Headquarters';
        $('sumOffice').textContent = o ? money((o.gross ?? o.price)) : '–';
        $('sumTotal').textContent = o ? money(state.regFee + (o.gross ?? o.price)) : '–';
        $('bank').textContent = money(state.bank);
        const name = $('orgName').value.trim();
        const nameOk = name.length >= (state.nameMin || 3);
        $('st1').classList.toggle('on', !nameOk);
        $('st2').classList.toggle('on', nameOk && !o);
        $('st3').classList.toggle('on', nameOk && !!o);
        $('registerBtn').disabled = !(nameOk && o) || state.creating;
    }

    function pick(id) {
        selected = id;
        const o = state.offices.find(x => x.id === id);
        if (o && map) map.focus(o.x, o.y, 0.35);
        renderRegister();
    }

    function renderMine() {
        const c = state.company;
        const hq = OSA.arr(c.units).find(u => u.id === c.hqUnit);
        const cur = hq ? hq.propertyId : null;
        const hqOffice = state.offices.find(x => x.id === cur);
        $('myName').textContent = c.name;
        $('myHeroImg').innerHTML = photo(hq && hq.building, hq ? hq.name : '');
        $('myHeroSub').textContent = (hq ? `Headquarters: ${hq.name}${hqOffice && hqOffice.city ? ', ' + hqOffice.city : ''} · ` : '') +
            'Manage it on the computer in your office.';
        $('myValue').textContent = money(c.value);
        $('myHq').textContent = hq ? hq.name : '–';
        $('myFounded').textContent = date(c.createdAt);
        const list = $('moveList');
        list.innerHTML = state.offices.map(o => officeRow(o, o.id === moveTo, o.id === cur)).join('');
        for (const el of list.querySelectorAll('.br-office')) {
            el.addEventListener('click', () => { if (el.dataset.id !== cur) { moveTo = el.dataset.id; renderMine(); } });
        }
        if (!map2) map2 = new OSA.Map($('map2'), { maxZoom: 3 });
        drawPins(map2, 'm:', cur, moveTo, id => { if (id !== cur) { moveTo = id; renderMine(); } });
        const o = state.offices.find(x => x.id === moveTo);
        $('moveBtn').disabled = !o;
        $('moveBtn').textContent = o ? 'Move headquarters (' + money((o.gross ?? o.price)) + ')' : 'Move headquarters';
    }

    async function load() {
        let r;
        try { r = await api.call('bwState'); } catch (e) { r = null; }
        $('regLoading').hidden = true;
        if (!r || !r.ok) {
            $('regLoading').hidden = false;
            $('regLoading').textContent = errText(r);
            return;
        }
        state = r;
        state.offices = OSA.arr(state.offices);
        if (state.company) {
            $('tabRegister').textContent = 'My organization';
            $('regForm').hidden = true;
            $('myOrg').hidden = false;
            renderMine();
        } else {
            $('tabRegister').textContent = 'Register';
            $('myOrg').hidden = true;
            $('regForm').hidden = false;
            if (!$('orgName').value) $('orgName').value = state.defaultName || '';
            $('nameHint').textContent = `${state.nameMin}–${state.nameMax} characters. It can be changed later for a fee.`;
            renderRegister();
            if (state.creating) msg($('regMsg'), 'Registering…', true);
        }
    }

    $('orgName').addEventListener('input', () => { if (state && !state.company) renderRegister(); });

    $('registerBtn').addEventListener('click', async () => {
        const btn = $('registerBtn');
        btn.disabled = true;
        msg($('regMsg'), 'Registering…', true);
        let r;
        try { r = await api.call('bwRegister', $('orgName').value.trim(), selected); } catch (e) { r = null; }
        if (!r || !r.ok) { msg($('regMsg'), errText(r), false); btn.disabled = false; return; }
        // finished asynchronously: wait until the organization exists
        let tries = 0;
        clearInterval(pendingPoll);
        pendingPoll = setInterval(async () => {
            tries++;
            await load();
            if ((state && state.company) || tries > 20) {
                clearInterval(pendingPoll);
                if (state && !state.company) { msg($('regMsg'), 'The registration did not go through. Your money was refunded.', false); btn.disabled = false; }
                else OSA.toast('Organization registered', true);
            }
        }, 1000);
    });

    $('moveBtn').addEventListener('click', async () => {
        if (!moveTo) return;
        const o = state.offices.find(x => x.id === moveTo);
        const ok = await OSA.ui.confirm('Move headquarters',
            `Move to ${o.name} for ${money((o.gross ?? o.price))} from the company account? The current office is bought back at half its price.`, 'Move');
        if (!ok) return;
        let r;
        try { r = await api.call('bwMoveHeadquarters', moveTo); } catch (e) { r = null; }
        if (!r || !r.ok) return msg($('moveMsg'), errText(r), false);
        msg($('moveMsg'), 'Moving…', true);
        moveTo = null;
        setTimeout(load, 1500);
    });

    // ------------------------------------------------------------ registry / top
    function hqCell(e) {
        if (!e.hq) return '–';
        return `<div class="br-hq"><span class="th">${photo(e.hqBuilding)}</span><span>${esc(e.hq)}${e.hqCity ? `<div class="br-small">${esc(e.hqCity)}</div>` : ''}</span></div>`;
    }
    let searchTimer = null;
    async function loadRegistry() {
        let r;
        try { r = await api.call('bwRegistry', $('search').value.trim()); } catch (e) { r = null; }
        const rows = r && r.ok ? OSA.arr(r.rows) : [];
        $('regRows').innerHTML = rows.length ? rows.map(e => `<tr>
            <td><b>${esc(e.name)}</b></td><td>${esc(OSA.clean(e.founder))}</td>
            <td>${hqCell(e)}</td>
            <td>${tags(e.activities)}</td><td>${date(e.createdAt)}</td></tr>`).join('')
            : `<tr><td colspan="5" class="br-empty">${r && r.ok ? 'No organization found.' : esc(errText(r))}</td></tr>`;
    }
    $('search').addEventListener('input', () => { clearTimeout(searchTimer); searchTimer = setTimeout(loadRegistry, 300); });

    async function loadTop() {
        let r;
        try { r = await api.call('bwTop'); } catch (e) { r = null; }
        const rows = r && r.ok ? OSA.arr(r.rows) : [];
        $('topRows').innerHTML = rows.length ? rows.map(e => `<tr>
            <td class="rank">${e.rank}</td><td><b>${esc(e.name)}</b></td><td>${esc(OSA.clean(e.founder))}</td>
            <td>${hqCell(e)}</td><td>${tags(e.activities)}</td><td class="num"><b>${money(e.value)}</b></td></tr>`).join('')
            : `<tr><td colspan="6" class="br-empty">${r && r.ok ? 'No organization yet.' : esc(errText(r))}</td></tr>`;
    }

    load();
})();
