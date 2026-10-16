// Shared by every pt_web page: links between the pages and the small UI helpers.
// Over HTTP a page is /pt_web/<name>.html (the home page is /pt_web/); in game every page is
// opened through web_api's loader, so a link keeps the loader and swaps its ?page=.
(function () {
    'use strict';

    const PT = window.PT = {};
    const esc = OSA.esc;

    PT.page = () => {
        if (OSA.inGame) {
            const p = new URLSearchParams(location.search).get('page') || 'web/index.html';
            return p.replace(/^web\//, '').replace(/\.html$/, '');
        }
        const m = location.pathname.match(/\/([^/]+)\.html$/);
        return m ? m[1] : 'index';
    };

    // name: page ("index" | "map"), params: extra query values, hash: section id
    PT.pageUrl = function (name, params, hash) {
        let q;
        let url;
        if (OSA.inGame) {
            q = new URLSearchParams(location.search);
            q.set('page', 'web/' + name + '.html');
            for (const k of ['station', 'from', 'to']) q.delete(k);
            url = location.pathname;
        } else {
            q = new URLSearchParams();
            url = name === 'index' ? '/pt_web/' : '/pt_web/' + name + '.html';
        }
        for (const k in params || {}) q.set(k, params[k]);
        const qs = q.toString();
        return url + (qs ? '?' + qs : '') + (hash ? '#' + hash : '');
    };

    // <a data-goto="map" data-hash="plan">: the right url in both modes; a link to a section of
    // the current page only scrolls
    function wire() {
        const here = PT.page();
        document.querySelectorAll('a[data-goto]').forEach(a => {
            const page = a.dataset.goto, hash = a.dataset.hash;
            a.href = PT.pageUrl(page, null, hash);
            if (page === here && hash) {
                a.addEventListener('click', ev => {
                    const el = document.getElementById(hash);
                    if (el) { ev.preventDefault(); el.scrollIntoView({ behavior: 'smooth' }); }
                });
            }
        });
    }
    OSA.ready(wire);

    /* ---------------------------------------------------------------- modes */
    const ICON = {
        rail: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2c-4 0-8 .5-8 4v9.5A3.5 3.5 0 0 0 7.5 19L6 20.5v.5h2.2l2-2h3.6l2 2H18v-.5L16.5 19a3.5 3.5 0 0 0 3.5-3.5V6c0-3.5-3.6-4-8-4zM7.5 17a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm3.5-7H6V6h5v4zm2 0V6h5v4h-5zm3.5 7a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z"/></svg>',
        bus: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 16c0 .9.4 1.7 1 2.2V20a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1h8v1a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1.8c.6-.5 1-1.3 1-2.2V6c0-3.5-3.6-4-8-4S4 2.5 4 6v10zm3.5 1a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm9 0a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm1.5-6H6V6h12v5z"/></svg>',
        walk: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="13" cy="4" r="2" fill="currentColor" stroke="none"/><path d="M13 8l-2 6 3 3v5M11 14l-3 8M11 9l-4 2v3M13 8l3 4h3"/></svg>',
    };
    PT.icon = mode => ICON[mode] || ICON.rail;
    PT.modeName = mode => ({ rail: 'Train', bus: 'Bus', walk: 'Walk' }[mode] || mode);
    // chip: mode icon + text
    PT.chip = (mode, text, title) =>
        `<span class="pt-mode ${esc(mode)}"${title ? ` title="${esc(title)}"` : ''}>${PT.icon(mode)}${esc(text)}</span>`;

    PT.duration = min => {
        min = Math.max(0, Math.round(min));
        return min < 60 ? min + ' min' : Math.floor(min / 60) + ' h ' + (min % 60) + ' min';
    };

    /* ---------------------------------------------------------------- header clock */
    let offset = 0;    // server seconds of day minus local
    PT.syncClock = serverSec => {
        const d = new Date();
        offset = serverSec - (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds());
    };
    PT.nowSec = () => {
        const d = new Date();
        return d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + offset;
    };
})();
