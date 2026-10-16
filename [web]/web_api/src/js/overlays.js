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
