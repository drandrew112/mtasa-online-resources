// gov_votes - /vote: the open state votes for every logged-in player. The page runs on gov_core's
// relay (client/panel.lua there): GOV.call(action, args), GOV._init / _resolve / _escape.
(function () {
    'use strict';
    const esc = OSA.esc;
    const arr = OSA.arr;
    const $ = id => document.getElementById(id);
    const view = $('view');
    const inGame = !!(window.mta && mta.triggerEvent);

    const KEYS = [
        ...['vote_page_title', 'vote_page_sub', 'vote_ends', 'voters_n', 'vote_cast', 'vote_change', 'vote_yours',
            'vote_none_open', 'results_after_close'].map(k => 'gov_votes.ui.' + k),
        ...['close', 'loading'].map(k => 'gov_core.ui.' + k),
    ];
    let STR = {};
    const T = (key, params) => {
        const full = STR['gov_votes.ui.' + key] !== undefined ? 'gov_votes.ui.' + key : 'gov_core.ui.' + key;
        const s = STR[full] !== undefined ? STR[full] : key.replace(/_/g, ' ');
        return params ? String(s).replace(/\{(\w+)\}/g, (m, k) => params[k] ?? m) : String(s);
    };
    const left = sec => {
        sec = Math.max(0, Math.round(sec));
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
    };

    const GOV = window.GOV = {};
    const waiting = {};
    let nextId = 0;
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
    const close = () => { if (inGame) mta.triggerEvent('gov_core:pageClose'); };
    GOV._escape = close;
    $('closeBtn').addEventListener('click', close);

    let data = null, offset = 0, busy = false;

    async function load() {
        try {
            data = await GOV.call('voteList');
            offset = data.now - Date.now() / 1000;
        } catch (e) { OSA.toast(e.message, false); }
        render();
    }

    function render() {
        const list = arr(data && data.list);
        if (!data) return;
        if (!list.length) { view.innerHTML = `<div class="gv-card gv-empty">${esc(T('vote_none_open'))}</div>`; return; }
        const now = Date.now() / 1000 + offset;
        view.innerHTML = list.map(v => {
            const opts = arr(v.options);
            return `<div class="gv-card"><div class="gv-head"><h2 style="margin:0;font-size:22px;color:var(--osa-text)">${esc(v.title)}</h2>` +
                `<span class="gv-sub">${esc(T('vote_ends'))} ${left(v.endsAt - now)} · ${esc(T('voters_n', { n: v.voters }))}</span></div>` +
                (v.description ? `<p class="gv-desc">${esc(v.description)}</p>` : '') +
                `<div class="gv-choices">${opts.map((o, i) => `<button class="gv-choice${v.mine === i + 1 ? ' on' : ''}" data-vote="${v.id}" data-opt="${i + 1}">` +
                    `<span>${esc(o)}</span>${v.mine === i + 1 ? `<small>${esc(T('vote_yours'))}</small>` : ''}</button>`).join('')}</div>` +
                `<div class="gv-sub" style="margin-top:10px">${esc(v.mine ? T('vote_change') : T('vote_cast'))} ${esc(T('results_after_close'))}</div></div>`;
        }).join('');
    }

    view.addEventListener('click', async e => {
        const b = e.target.closest('[data-vote]');
        if (!b || busy) return;
        busy = true;
        try {
            await GOV.call('voteCast', { id: Number(b.dataset.vote), option: Number(b.dataset.opt) });
        } catch (err) { OSA.toast(err.message, false); }
        busy = false;
        load();
    });

    GOV._init = d => {
        STR = d.strings || {};
        $('title').textContent = T('vote_page_title');
        $('sub').textContent = T('vote_page_sub');
        $('closeBtn').textContent = T('close') + ' (Esc)';
        document.title = T('vote_page_title');
        load();
        setInterval(render, 30000);
    };

    if (inGame) mta.triggerEvent('gov_core:pageReady', JSON.stringify([KEYS]));
    else view.innerHTML = '<div class="gv-empty">Open it in game with /vote.</div>';
})();
