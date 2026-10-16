    /* ====================================================================== transport */
    /* Over HTTP an exported function is called as  POST /<resource>/call/<fn>  (JSON array of
       arguments, JSON array of return values). In game there is no HTTP: the call goes through
       mta.triggerEvent -> web_api client -> server (web_api/server/bridge.lua) and the answer
       comes back through OSA._resolve. Both give the FIRST return value, so a page does not
       care where it runs. Only exports marked http="true" in meta.xml can be called. */

    const pending = {};
    let seq = 0;

    OSA._resolve = function (id, data) {
        const p = pending[id];
        if (!p) return;
        delete pending[id];
        clearTimeout(p.timer);
        p.resolve(Array.isArray(data) ? data[0] : data);
    };

    function bridgeCall(fn, args, timeout) {
        return new Promise((resolve, reject) => {
            const id = ++seq;
            pending[id] = {
                resolve,
                timer: setTimeout(() => { delete pending[id]; reject(new Error('timeout')); }, timeout),
            };
            mta.triggerEvent('osa:web:call', String(id), fn, JSON.stringify(args));
        });
    }

    async function httpCall(app, fn, args, timeout) {
        const ctl = new AbortController();
        const timer = setTimeout(() => ctl.abort(), timeout);
        try {
            const res = await fetch('/' + app + '/call/' + fn, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(args),
                signal: ctl.signal,
            });
            if (!res.ok) throw new Error('HTTP ' + res.status);
            const data = await res.json();
            return Array.isArray(data) ? data[0] : data;
        } catch (e) {
            throw e.name === 'AbortError' ? new Error('timeout') : e;
        } finally {
            clearTimeout(timer);
        }
    }

    // OSA.api()                 -> the page's own resource
    // OSA.api('other_resource') -> another resource (HTTP only; in game a page can only reach its own)
    // await api.call('fnName', arg1, arg2) -> first return value of the exported function
    OSA.api = function (app, opts) {
        app = app || OSA.app;
        const timeout = (opts && opts.timeout) || 15000;
        return {
            app,
            inGame: OSA.inGame,
            call: (fn, ...args) => OSA.inGame ? bridgeCall(fn, args, timeout) : httpCall(app, fn, args, timeout),
        };
    };
