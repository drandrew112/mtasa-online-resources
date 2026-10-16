    const metaVal = n => {
        const m = document.querySelector('meta[name="osa-' + n + '"]');
        return m ? m.content : '';
    };
    const hasMta = typeof mta !== 'undefined' && mta && typeof mta.triggerEvent === 'function';
    const mode = metaVal('mode');

    const OSA = window.OSA = {
        version: '1.0.0',
        // resource name of the page: the page builder / loader writes it into <meta name="osa-app">
        app: metaVal('app') || location.pathname.split('/').filter(Boolean)[0] || '',
        inGame: mode ? mode === 'game' : hasMta,
    };

    const create = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    };

    /* ====================================================================== helpers */

    // MTA encodes empty Lua tables as {} - normalise to arrays
    OSA.arr = x => Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []);

    OSA.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));

    // MTA colour codes (#RRGGBB) out of nicknames
    OSA.clean = s => String(s ?? '').replace(/#[0-9a-f]{6}/gi, '');

    OSA.store = {
        get(k, d) { try { return localStorage.getItem(k) ?? d; } catch (e) { return d; } },
        set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignore */ } },
    };

    // Pages carry a <base href> (app folder), which turns every href="#section" into a link to the
    // base url instead of the current page - handle in-page anchors here.
    document.addEventListener('click', ev => {
        if (ev.defaultPrevented || ev.button !== 0 || ev.ctrlKey || ev.metaKey || ev.shiftKey) return;
        const a = ev.target.closest && ev.target.closest('a[href^="#"]');
        if (!a || a.target === '_blank') return;
        const id = decodeURIComponent(a.getAttribute('href').slice(1));
        ev.preventDefault();
        const el = id ? document.getElementById(id) : null;
        try { history.replaceState(null, '', id ? '#' + id : location.pathname + location.search); } catch (e) { /* ignore */ }
        window.dispatchEvent(new HashChangeEvent('hashchange'));
        if (el) el.scrollIntoView({ behavior: 'smooth' });
        else if (!id) window.scrollTo({ top: 0, behavior: 'smooth' });
    });

    OSA.ready = fn => {
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
        else fn();
    };
