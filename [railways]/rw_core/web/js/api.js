// Shared helpers + call wrapper. Over HTTP the exported functions are called as
// POST /<resource>/call/<fn> (JSON args array, JSON array of results). In game (ui_browser,
// local CEF page) there is no HTTP: calls go through mta.triggerEvent and come back through
// RWWEB._bridgeResolve(id, [result]).
(function () {
    'use strict';

    const resource = location.pathname.split('/').filter(Boolean)[0] || 'rw_core';
    const RWWEB = window.RWWEB = { resource };

    RWWEB.inGame = typeof mta !== 'undefined' && typeof mta.triggerEvent === 'function';
    const pending = {};
    let seq = 0;

    RWWEB._bridgeResolve = function (id, data) {
        const p = pending[id];
        if (!p) return;
        delete pending[id];
        clearTimeout(p.timer);
        p.resolve(Array.isArray(data) ? data[0] : data);
    };

    function bridgeCall(fn) {
        return new Promise((resolve, reject) => {
            const id = ++seq;
            pending[id] = {
                resolve,
                timer: setTimeout(() => { delete pending[id]; reject(new Error('timeout')); }, 10000),
            };
            mta.triggerEvent('rw:web:call', String(id), fn);
        });
    }

    RWWEB.call = async function (fn) {
        if (RWWEB.inGame) return bridgeCall(fn);
        const res = await fetch('/' + resource + '/call/' + fn, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: '[]',
        });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const data = await res.json();
        return Array.isArray(data) ? data[0] : data;
    };

    // MTA encodes empty Lua tables as {} - normalise to arrays
    RWWEB.arr = x => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);

    RWWEB.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));

    // seconds of the day -> "HH:MM"
    RWWEB.hhmm = s => {
        if (s === undefined || s === null || s === false) return '';
        s = ((Math.round(s) % 86400) + 86400) % 86400;
        return String(Math.floor(s / 3600)).padStart(2, '0') + ':' + String(Math.floor(s % 3600 / 60)).padStart(2, '0');
    };

    // delay in seconds -> "+2 min" / "on time"
    RWWEB.delay = d => {
        if (d === undefined || d === null || d === false) return { text: '', cls: '' };
        const m = Math.round(d / 60);
        if (m >= 1) return { text: '+' + m + ' min', cls: 'late' };
        if (m <= -1) return { text: m + ' min', cls: 'early' };
        return { text: 'on time', cls: 'ontime' };
    };
})();
