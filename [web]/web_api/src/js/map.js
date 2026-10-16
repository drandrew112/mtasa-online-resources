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

    // "Provided by OpenSanAndreas" sits in the bottom-left corner of the map (the map tiles come
    // from OpenSanAndreas); a page without a map gets no credit
    function credit() {
        if (document.querySelector('.osa-credit')) return;
        const wrap = document.querySelector('.osa-map-wrap');
        if (!wrap) return;
        const d = create('div', 'osa-credit');
        d.append('Provided by ');
        d.appendChild(create('b', '', 'OpenSanAndreas'));
        wrap.appendChild(d);
    }
    OSA.ready(credit);
