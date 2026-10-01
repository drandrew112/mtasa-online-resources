// Shared helpers + MTA HTTP call wrapper.
// Exported functions are called as POST /<resource>/call/<fn> with a JSON
// array of arguments; MTA answers with a JSON array of return values.
(function () {
    'use strict';

    const resource = location.pathname.split('/').filter(Boolean)[0] || 'erm';
    const store = {
        get(k, d) { try { return localStorage.getItem(k) ?? d; } catch (e) { return d; } },
        set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } },
    };

    const ERM = window.ERM = {
        resource,
        store,
        token: null,       // session token, memory only (reload = login again)
        serverOffset: 0,   // server epoch - local epoch (seconds)
    };

    // In game (ui_browser, local CEF page) there is no HTTP: calls go through
    // mta.triggerEvent -> erm client -> server, answers come back through
    // ERM._bridgeResolve(id, [result]) (executeBrowserJavascript).
    ERM.inGame = typeof mta !== 'undefined' && typeof mta.triggerEvent === 'function';
    const pending = {};
    let seq = 0;

    ERM._bridgeResolve = function (id, data) {
        const p = pending[id];
        if (!p) return;
        delete pending[id];
        clearTimeout(p.timer);
        p.resolve(Array.isArray(data) ? data[0] : data);
    };

    function bridgeCall(fn, args) {
        return new Promise((resolve, reject) => {
            const id = ++seq;
            pending[id] = {
                resolve,
                timer: setTimeout(() => {
                    delete pending[id];
                    reject(new Error('timeout'));
                }, 15000),
            };
            mta.triggerEvent('erm:web:call', String(id), fn, JSON.stringify([ERM.token, ...args]));
        });
    }

    ERM.call = async function (fn, ...args) {
        if (ERM.inGame) return bridgeCall(fn, args);
        const res = await fetch('/' + resource + '/call/' + fn, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify([ERM.token, ...args]),
        });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        const data = await res.json();
        return Array.isArray(data) ? data[0] : data;
    };

    // MTA encodes empty Lua tables as {} - normalise to arrays.
    ERM.arr = x => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);

    ERM.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));

    // MTA colour codes (#RRGGBB) out of nicknames
    ERM.clean = s => String(s ?? '').replace(/#[0-9a-f]{6}/gi, '');

    ERM.now = () => Math.floor(Date.now() / 1000) + ERM.serverOffset;

    ERM.clock = ts => {
        const d = new Date(ts * 1000);
        return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
    };

    ERM.age = ts => {
        const s = Math.max(0, ERM.now() - ts);
        if (s < 60) return s + 's';
        if (s < 3600) return Math.floor(s / 60) + 'm';
        return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
    };

    ERM.STATUS = {
        available: 'Available',
        enroute: 'En Route',
        onscene: 'On Scene',
        handover: 'Handover',
    };

    ERM.TASK_STATUS = {
        unassigned: 'Not assigned',
        prioritized: 'Prioritized',
        assigned: 'Assigned',
        closed: 'Closed',
    };

    ERM.toast = function (text, ok) {
        const el = document.createElement('div');
        el.className = 'toast' + (ok ? ' ok' : '');
        el.textContent = text;
        document.getElementById('toasts').appendChild(el);
        setTimeout(() => el.remove(), 3500);
    };

    // Runs an API action and reports its error, if any.
    ERM.act = async function (fn, ...args) {
        try {
            const r = await ERM.call(fn, ...args);
            if (r && r.error === 'unauthorized') {
                ERM.app.lock();
                return null;
            }
            if (!r || r.ok === false) {
                ERM.toast((r && r.error) || 'Request failed');
                return null;
            }
            ERM.app && ERM.app.refresh();
            return r;
        } catch (e) {
            ERM.toast('Server unreachable: ' + e.message);
            return null;
        }
    };
})();
