/* ============================================================================
   OSA web toolkit - shared script (web_api/osa.js)          Provided by OpenSanAndreas

   One script for pages that run in two places:
     - a normal browser over MTA HTTP   (http://<server>:<httpport>/<resource>/)
     - the in-game browser (ui_browser, a local CEF page)

   Parts:  OSA.api()      call an http="true" export of the page's resource
           OSA.esc / arr / clean / hhmm / clock / age / delay / time   helpers
           OSA.toast / OSA.ui.openMenu / showTip / form / confirm      overlays
           OSA.Map        pan / zoom map on the v_radar bigmap (+ markers, canvas layers)
           OSA.poll       self-scheduling poll loop
           the "Provided by OpenSanAndreas" credit (added automatically)
   ========================================================================== */
(function () {
    'use strict';
    if (window.OSA) return;

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

    const two = n => String(n).padStart(2, '0');

    // seconds of the day -> "HH:MM"
    OSA.hhmm = s => {
        if (s === undefined || s === null || s === false) return '';
        s = ((Math.round(s) % 86400) + 86400) % 86400;
        return two(Math.floor(s / 3600)) + ':' + two(Math.floor(s % 3600 / 60));
    };

    // epoch seconds -> local "HH:MM"
    OSA.clock = ts => {
        const d = new Date(ts * 1000);
        return two(d.getHours()) + ':' + two(d.getMinutes());
    };

    // delay in seconds -> { text: "+2 min" | "on time", cls: "late" | "early" | "ontime" }
    OSA.delay = d => {
        if (d === undefined || d === null || d === false) return { text: '', cls: '' };
        const m = Math.round(d / 60);
        if (m >= 1) return { text: '+' + m + ' min', cls: 'late' };
        if (m <= -1) return { text: m + ' min', cls: 'early' };
        return { text: 'on time', cls: 'ontime' };
    };

    // server clock: sync(serverEpochSeconds) on every answer, now() = server epoch seconds
    OSA.time = {
        offset: 0,
        sync(serverEpoch) { OSA.time.offset = serverEpoch - Math.floor(Date.now() / 1000); },
        now() { return Math.floor(Date.now() / 1000) + OSA.time.offset; },
    };

    // epoch seconds -> "12s" / "5m" / "1h 20m" ago
    OSA.age = ts => {
        const s = Math.max(0, OSA.time.now() - ts);
        if (s < 60) return s + 's';
        if (s < 3600) return Math.floor(s / 60) + 'm';
        return Math.floor(s / 3600) + 'h ' + Math.floor((s % 3600) / 60) + 'm';
    };

    OSA.ready = fn => {
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
        else fn();
    };

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

    /* ====================================================================== poll */

    // Runs fn() now and then every `ms` after it finished (never overlapping).
    // opts: onOk(), onFail(consecutiveFailures, error). Returns { stop(), now() }.
    OSA.poll = function (fn, ms, opts) {
        opts = opts || {};
        let timer = null, stopped = false, running = false, again = false, fails = 0;
        async function run() {
            if (running) { again = true; return; }
            running = true;
            clearTimeout(timer);
            try {
                await fn();
                fails = 0;
                if (opts.onOk) opts.onOk();
            } catch (e) {
                fails++;
                if (opts.onFail) opts.onFail(fails, e);
            }
            running = false;
            if (stopped) return;
            if (again) { again = false; return run(); }
            timer = setTimeout(run, typeof ms === 'function' ? ms() : ms);
        }
        run();
        return { stop() { stopped = true; clearTimeout(timer); }, now: run };
    };

    /* ====================================================================== toast */

    let toasts = null;
    OSA.toast = function (text, ok) {
        if (!toasts || !toasts.isConnected) {
            toasts = create('div', 'osa-toasts');
            document.body.appendChild(toasts);
        }
        const t = create('div', 'osa-toast' + (ok ? ' ok' : ''), text);
        toasts.appendChild(t);
        setTimeout(() => t.remove(), 3500);
    };

    /* ====================================================================== overlays */

    const ui = OSA.ui = {};
    let ctxEl = null, tipEl = null, modalEl = null, modalBox = null;
    let tipSource = null, modalCancel = null;

    function overlays() {
        if (ctxEl && ctxEl.isConnected) return;
        ctxEl = create('div', 'osa-ctx'); ctxEl.hidden = true;
        tipEl = create('div', 'osa-tip'); tipEl.hidden = true;
        modalEl = create('div', 'osa-modal-back'); modalEl.hidden = true;
        modalBox = create('div', 'osa-modal');
        modalEl.appendChild(modalBox);
        document.body.append(ctxEl, tipEl, modalEl);

        document.addEventListener('mousedown', e => { if (!ctxEl.contains(e.target)) ui.closeMenu(); });
        document.addEventListener('keydown', e => { if (e.key === 'Escape') { ui.closeMenu(); ui.closeModal(); } });
        window.addEventListener('blur', () => ui.closeMenu());
        modalEl.addEventListener('mousedown', e => { if (e.target === modalEl) ui.closeModal(); });
    }

    /* ---- context menu. items: { label, action, disabled, danger, dot } | { header } | 'sep' */
    ui.openMenu = function (x, y, items) {
        overlays();
        ui.hideTip();
        ctxEl.textContent = '';
        for (const it of items) {
            if (it === 'sep') {
                ctxEl.appendChild(create('div', 'osa-ctx-sep'));
            } else if (it.header) {
                ctxEl.appendChild(create('div', 'osa-ctx-head', it.header));
            } else {
                const b = create('button', 'osa-ctx-item' + (it.danger ? ' danger' : ''));
                b.disabled = !!it.disabled;
                if (it.dot) {
                    const d = create('span', 'osa-dot');
                    d.style.background = it.dot;
                    b.appendChild(d);
                }
                b.appendChild(document.createTextNode(it.label));
                b.addEventListener('click', () => { ui.closeMenu(); if (it.action) it.action(); });
                ctxEl.appendChild(b);
            }
        }
        ctxEl.hidden = false;
        const r = ctxEl.getBoundingClientRect();
        ctxEl.style.left = Math.max(4, Math.min(x, innerWidth - r.width - 8)) + 'px';
        ctxEl.style.top = Math.max(4, Math.min(y, innerHeight - r.height - 8)) + 'px';
    };
    ui.closeMenu = function () { if (ctxEl) ctxEl.hidden = true; };

    /* ---- tooltip. `source` identifies who owns it so a stale hide does not close another's */
    ui.showTip = function (source, html, e) {
        overlays();
        tipSource = source;
        tipEl.innerHTML = html;
        tipEl.hidden = false;
        ui.moveTip(e);
    };
    ui.moveTip = function (e) {
        if (!tipEl || tipEl.hidden || !e) return;
        const r = tipEl.getBoundingClientRect();
        let x = e.clientX + 14, y = e.clientY + 14;
        if (x + r.width > innerWidth - 8) x = e.clientX - r.width - 14;
        if (y + r.height > innerHeight - 8) y = e.clientY - r.height - 14;
        tipEl.style.left = Math.max(4, x) + 'px';
        tipEl.style.top = Math.max(4, y) + 'px';
    };
    ui.hideTip = function (source) {
        if (!tipEl) return;
        if (source && source !== tipSource) return;
        tipSource = null;
        tipEl.hidden = true;
    };
    // refreshes the tooltip content while it is shown (live data)
    ui.updateTip = function (source, html) {
        if (tipEl && tipSource === source && !tipEl.hidden) tipEl.innerHTML = html;
    };

    /* ---- modal dialogs */
    ui.closeModal = function () {
        if (!modalEl || modalEl.hidden) return;
        modalEl.hidden = true;
        const c = modalCancel;
        modalCancel = null;
        if (c) c();
    };

    // fields: [{ name, label, type: 'text'|'textarea'|..., value, placeholder }]
    // -> Promise of { name: trimmed value } or null when cancelled
    ui.form = function (title, fields, submitLabel, hint) {
        overlays();
        ui.closeModal();
        return new Promise(resolve => {
            modalBox.innerHTML = '<h3>' + OSA.esc(title) + '</h3>' + (hint ? '<p class="osa-hint">' + OSA.esc(hint) + '</p>' : '');
            const f = create('form');
            for (const fd of fields) {
                const l = create('label', '', fd.label);
                const input = create(fd.type === 'textarea' ? 'textarea' : 'input');
                input.name = fd.name;
                input.value = fd.value || '';
                input.placeholder = fd.placeholder || '';
                if (fd.type && fd.type !== 'textarea') input.type = fd.type;
                l.appendChild(input);
                f.appendChild(l);
            }
            const row = create('div', 'osa-row');
            const cancel = create('button', 'osa-btn', 'Cancel');
            cancel.type = 'button';
            const submit = create('button', 'osa-btn primary', submitLabel || 'OK');
            submit.type = 'submit';
            row.append(cancel, submit);
            f.appendChild(row);
            modalBox.appendChild(f);

            const done = v => { modalCancel = null; ui.closeModal(); resolve(v); };
            cancel.addEventListener('click', () => done(null));
            f.addEventListener('submit', e => {
                e.preventDefault();
                const out = {};
                for (const fd of fields) out[fd.name] = f.elements[fd.name].value.trim();
                done(out);
            });
            modalCancel = () => resolve(null);
            modalEl.hidden = false;
            const first = f.querySelector('input, textarea');
            if (first) first.focus();
        });
    };

    // -> Promise<boolean>
    ui.confirm = function (title, text, okLabel) {
        overlays();
        ui.closeModal();
        return new Promise(resolve => {
            modalBox.innerHTML = '<h3>' + OSA.esc(title) + '</h3>' + (text ? '<p>' + OSA.esc(text) + '</p>' : '');
            const row = create('div', 'osa-row');
            const cancel = create('button', 'osa-btn', 'Cancel');
            const ok = create('button', 'osa-btn primary', okLabel || 'OK');
            row.append(cancel, ok);
            modalBox.appendChild(row);
            const done = v => { modalCancel = null; ui.closeModal(); resolve(v); };
            cancel.addEventListener('click', () => done(false));
            ok.addEventListener('click', () => done(true));
            modalCancel = () => resolve(false);
            modalEl.hidden = false;
            ok.focus();
        });
    };

    /* ====================================================================== map */
    /* Pan / zoom map on the v_radar bigmap. The image covers the world square
       (-world/2 .. world/2, default 6000 -> -3000..3000) whatever its pixel size - it is laid
       out at a fixed logical `size`, so a 3072 or 4096 px radar.png behaves the same.

         const map = new OSA.Map(document.getElementById('map'), { ...options });
         map.marker(key, worldX, worldY, 'class names', 'inner html', onClick) -> element
         map.removeMissing('prefix:', new Set(keysToKeep))
         map.addLayer((ctx, map) => { ... })        canvas drawn under the markers (map.toScreen)
         map.fit() / fitBox(minX, minY, maxX, maxY, pad) / focus(x, y, minZoom)
       Events on map.el:  mapmove, mapclick {wx, wy}, mapcontext {wx, wy, event}

       options: image, world, size, maxZoom, focusZoom, tools (zoom buttons, default true),
                onFit (replaces the fit button), autoFit (fit once when shown, default true),
                onMarkerCreate(el, key) */
    class OSAMap {
        constructor(el, opts) {
            this.opts = Object.assign({
                image: '/v_radar/radar/files/radar.png',
                world: 6000, size: 3072,
                maxZoom: 3, focusZoom: 0.6,
                tools: true, onFit: null, autoFit: true, onMarkerCreate: null,
            }, opts);
            this.el = el;
            this.zoom = 0.2; this.ox = 0; this.oy = 0; this.minZoom = 0.1;
            this.fitted = false;
            this.markers = new Map();
            this.layers = [];
            this.canvas = null;

            el.classList.add('osa-map');
            el.textContent = '';
            this.img = create('img', 'osa-map-img');
            this.img.alt = '';
            this.img.draggable = false;
            this.img.style.width = this.img.style.height = this.opts.size + 'px';
            this.img.src = this.opts.image;
            this.layer = create('div', 'osa-map-markers');
            el.append(this.img, this.layer);

            this._input();
            if (this.opts.tools) this._tools();
            new ResizeObserver(() => this._resized()).observe(el);
        }

        on(type, fn) { this.el.addEventListener(type, fn); return this; }

        /* ---- coordinates (world <-> logical map px <-> screen px relative to the map) */
        toMap(x, y) {
            const o = this.opts;
            return [(x + o.world / 2) / o.world * o.size, (o.world / 2 - y) / o.world * o.size];
        }
        toScreen(x, y) {
            const [mx, my] = this.toMap(x, y);
            return [this.ox + mx * this.zoom, this.oy + my * this.zoom];
        }
        toWorld(sx, sy) {
            const o = this.opts;
            const mx = (sx - this.ox) / this.zoom, my = (sy - this.oy) / this.zoom;
            return [mx / o.size * o.world - o.world / 2, o.world / 2 - my / o.size * o.world];
        }

        /* ---- view */
        apply() {
            this.img.style.transform = `translate(${this.ox}px, ${this.oy}px) scale(${this.zoom})`;
            this.redraw();
            this.markers.forEach(m => this._place(m));
            this.el.dispatchEvent(new CustomEvent('mapmove'));
        }

        fit() {
            const r = this.el.getBoundingClientRect();
            if (!r.width || !r.height) return false;
            const s = this.opts.size;
            this.fitted = true;
            this.zoom = Math.min(r.width, r.height) / s;
            this.minZoom = this.zoom * 0.8;
            this.ox = (r.width - s * this.zoom) / 2;
            this.oy = (r.height - s * this.zoom) / 2;
            this.apply();
            return true;
        }

        fitBox(minX, minY, maxX, maxY, pad) {
            const r = this.el.getBoundingClientRect();
            if (!r.width || !r.height) return false;
            pad = pad === undefined ? 60 : pad;
            const [ax, ay] = this.toMap(minX, maxY), [bx, by] = this.toMap(maxX, minY);
            this.fitted = true;
            const z = Math.min((r.width - pad * 2) / (bx - ax), (r.height - pad * 2) / (by - ay));
            this.zoom = Math.max(this.minZoom, Math.min(this.opts.maxZoom, z));
            this.ox = r.width / 2 - (ax + bx) / 2 * this.zoom;
            this.oy = r.height / 2 - (ay + by) / 2 * this.zoom;
            this.apply();
            return true;
        }

        zoomAt(factor, cx, cy) {
            const nz = Math.max(this.minZoom, Math.min(this.opts.maxZoom, this.zoom * factor));
            this.ox = cx - (cx - this.ox) * nz / this.zoom;
            this.oy = cy - (cy - this.oy) * nz / this.zoom;
            this.zoom = nz;
            this.apply();
        }

        focus(x, y, minZ) {
            const r = this.el.getBoundingClientRect();
            this.zoom = Math.max(this.zoom, minZ || this.opts.focusZoom);
            const [mx, my] = this.toMap(x, y);
            this.ox = r.width / 2 - mx * this.zoom;
            this.oy = r.height / 2 - my * this.zoom;
            this.apply();
        }

        /* ---- markers */
        _place(m) {
            const [sx, sy] = this.toScreen(m._x, m._y);
            m._sx = sx;
            m._sy = sy;
            m.style.left = sx + 'px';
            m.style.top = (sy - (m._dy || 0)) + 'px';
        }

        // creates the marker on first use. cls: its own class names (other classes added to the
        // element from outside survive an update); html is re-rendered only when it changes.
        marker(key, x, y, cls, html, onClick) {
            let m = this.markers.get(key);
            if (!m) {
                m = create('div', 'osa-marker');
                m._key = key;
                if (onClick) m.addEventListener('click', ev => { ev.stopPropagation(); onClick(ev, m); });
                this.layer.appendChild(m);
                this.markers.set(key, m);
                if (this.opts.onMarkerCreate) this.opts.onMarkerCreate(m, key);
            }
            if (m._cls !== cls) {
                if (m._cls) m.classList.remove(...m._cls.split(' ').filter(Boolean));
                if (cls) m.classList.add(...cls.split(' ').filter(Boolean));
                m._cls = cls;
            }
            if (html !== undefined && m._html !== html) { m.innerHTML = html; m._html = html; }
            m._x = x;
            m._y = y;
            this._place(m);
            return m;
        }

        getMarker(key) { return this.markers.get(key); }

        removeMarker(key) {
            const m = this.markers.get(key);
            if (m) { m.remove(); this.markers.delete(key); }
            return m;
        }

        // removes the markers whose key starts with prefix and is not in the `keep` set
        removeMissing(prefix, keep) {
            this.markers.forEach((m, k) => {
                if (k.startsWith(prefix) && !keep.has(k)) this.removeMarker(k);
            });
        }

        /* ---- canvas layers (drawn below the markers, in screen coordinates) */
        addLayer(fn) {
            if (!this.canvas) {
                this.canvas = create('canvas', 'osa-map-canvas');
                this.el.insertBefore(this.canvas, this.layer);
                this._sizeCanvas();
            }
            this.layers.push(fn);
            this.redraw();
        }

        _sizeCanvas() {
            if (!this.canvas) return;
            const r = this.el.getBoundingClientRect();
            const dpr = window.devicePixelRatio || 1;
            this.canvas.width = Math.max(1, r.width * dpr);
            this.canvas.height = Math.max(1, r.height * dpr);
            this.canvas.style.width = r.width + 'px';
            this.canvas.style.height = r.height + 'px';
            this.canvas.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        redraw() {
            if (!this.canvas || !this.layers.length) return;
            const r = this.el.getBoundingClientRect();
            const ctx = this.canvas.getContext('2d');
            ctx.clearRect(0, 0, r.width, r.height);
            for (const fn of this.layers) fn(ctx, this, r);
        }

        _resized() {
            this._sizeCanvas();
            const r = this.el.getBoundingClientRect();
            if (r.width && r.height) this.minZoom = Math.min(r.width, r.height) / this.opts.size * 0.8;
            if (!this.fitted && this.opts.autoFit) this.fit(); else this.apply();
        }

        /* ---- input */
        _input() {
            const el = this.el;
            const rel = e => { const r = el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
            const onMarker = e => e.target.closest && e.target.closest('.osa-marker');

            el.addEventListener('wheel', e => {
                e.preventDefault();
                const [x, y] = rel(e);
                this.zoomAt(e.deltaY < 0 ? 1.2 : 1 / 1.2, x, y);
            }, { passive: false });

            let pan = null;
            el.addEventListener('mousedown', e => {
                if (e.button !== 0 || onMarker(e)) return;
                pan = { x: e.clientX, y: e.clientY, ox: this.ox, oy: this.oy };
                el.classList.add('panning');
            });
            window.addEventListener('mousemove', e => {
                if (!pan) return;
                this.ox = pan.ox + e.clientX - pan.x;
                this.oy = pan.oy + e.clientY - pan.y;
                this.apply();
            });
            window.addEventListener('mouseup', e => {
                if (!pan) return;
                const moved = Math.abs(e.clientX - pan.x) + Math.abs(e.clientY - pan.y);
                pan = null;
                el.classList.remove('panning');
                if (moved < 5) {
                    const [x, y] = rel(e);
                    const [wx, wy] = this.toWorld(x, y);
                    el.dispatchEvent(new CustomEvent('mapclick', { detail: { wx, wy, event: e } }));
                }
            });

            el.addEventListener('contextmenu', e => {
                e.preventDefault();
                if (onMarker(e)) return;
                const [x, y] = rel(e);
                const [wx, wy] = this.toWorld(x, y);
                el.dispatchEvent(new CustomEvent('mapcontext', { detail: { wx, wy, event: e } }));
            });

            // touch: one finger pans
            let touch = null;
            el.addEventListener('touchstart', e => {
                if (e.touches.length !== 1 || onMarker(e)) return;
                touch = { x: e.touches[0].clientX, y: e.touches[0].clientY, ox: this.ox, oy: this.oy };
            }, { passive: true });
            el.addEventListener('touchmove', e => {
                if (!touch || e.touches.length !== 1) return;
                this.ox = touch.ox + e.touches[0].clientX - touch.x;
                this.oy = touch.oy + e.touches[0].clientY - touch.y;
                this.apply();
            }, { passive: true });
            el.addEventListener('touchend', () => { touch = null; });
        }

        _tools() {
            const box = create('div', 'osa-map-tools');
            const btn = (txt, title, fn) => {
                const b = create('button', 'osa-btn icon', txt);
                b.title = title;
                b.addEventListener('click', fn);
                box.appendChild(b);
            };
            const center = factor => () => {
                const r = this.el.getBoundingClientRect();
                this.zoomAt(factor, r.width / 2, r.height / 2);
            };
            btn('+', 'Zoom in', center(1.4));
            btn('−', 'Zoom out', center(1 / 1.4));
            btn('⤢', 'Fit map', () => (this.opts.onFit ? this.opts.onFit() : this.fit()));
            (this.el.parentElement || document.body).appendChild(box);
            this.toolsEl = box;
        }
    }
    OSA.Map = OSAMap;

    /* ====================================================================== credit */

    // "Provided by OpenSanAndreas" sits in the bottom-left corner of the map; a page without a
    // map gets a strip at the bottom-left of the page instead
    function credit() {
        if (document.querySelector('.osa-credit')) return;
        const d = create('div', 'osa-credit');
        d.append('Provided by ');
        d.appendChild(create('b', '', 'OpenSanAndreas'));
        const wrap = document.querySelector('.osa-map-wrap');
        if (wrap) {
            wrap.appendChild(d);
        } else {
            d.classList.add('page');
            document.body.classList.add('osa-credit-page');
            document.body.appendChild(d);
        }
    }
    OSA.ready(credit);
})();
