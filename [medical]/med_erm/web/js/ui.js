// Context menu, tooltip and modal dialogs.
(function () {
    'use strict';

    const ctx = document.getElementById('ctx');
    const tip = document.getElementById('tooltip');
    const modal = document.getElementById('modal');
    const modalBox = document.getElementById('modalBox');

    /* ------------------------------------------------------------ context menu
       items: { label, action, disabled, danger, dot } | { header } | 'sep'      */

    function openMenu(x, y, items) {
        hideTip();
        ctx.innerHTML = '';
        for (const it of items) {
            if (it === 'sep') {
                ctx.appendChild(Object.assign(document.createElement('div'), { className: 'ctx-sep' }));
            } else if (it.header) {
                ctx.appendChild(Object.assign(document.createElement('div'), { className: 'ctx-head', textContent: it.header }));
            } else {
                const b = document.createElement('button');
                b.className = 'ctx-item' + (it.danger ? ' danger' : '');
                b.disabled = !!it.disabled;
                if (it.dot) b.innerHTML = `<span class="dot" style="background:${it.dot}"></span>`;
                b.appendChild(document.createTextNode(it.label));
                b.addEventListener('click', () => { closeMenu(); it.action && it.action(); });
                ctx.appendChild(b);
            }
        }
        ctx.hidden = false;
        const r = ctx.getBoundingClientRect();
        ctx.style.left = Math.min(x, innerWidth - r.width - 8) + 'px';
        ctx.style.top = Math.min(y, innerHeight - r.height - 8) + 'px';
    }

    function closeMenu() { ctx.hidden = true; }

    document.addEventListener('mousedown', e => { if (!ctx.contains(e.target)) closeMenu(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeMenu(); closeModal(); } });
    window.addEventListener('blur', closeMenu);

    /* ------------------------------------------------------------ tooltip */

    let tipSource = null;

    function showTip(source, html, e) {
        tipSource = source;
        tip.innerHTML = html;
        tip.hidden = false;
        moveTip(e);
    }

    function moveTip(e) {
        if (tip.hidden) return;
        const r = tip.getBoundingClientRect();
        let x = e.clientX + 14, y = e.clientY + 14;
        if (x + r.width > innerWidth - 8) x = e.clientX - r.width - 14;
        if (y + r.height > innerHeight - 8) y = e.clientY - r.height - 14;
        tip.style.left = x + 'px';
        tip.style.top = y + 'px';
    }

    function hideTip(source) {
        if (source && source !== tipSource) return;
        tipSource = null;
        tip.hidden = true;
    }

    // Refreshes the tooltip content while it is shown (live data).
    function updateTip(source, html) {
        if (tipSource === source && !tip.hidden) tip.innerHTML = html;
    }

    /* ------------------------------------------------------------ modal */

    // fields: [{ name, label, type: 'text'|'textarea', value, placeholder }]
    function form(title, fields, submitLabel, hint) {
        return new Promise(resolve => {
            modalBox.innerHTML = `<h3>${ERM.esc(title)}</h3>` + (hint ? `<p class="hint">${ERM.esc(hint)}</p>` : '');
            const f = document.createElement('form');
            for (const fd of fields) {
                const l = document.createElement('label');
                l.textContent = fd.label;
                const input = document.createElement(fd.type === 'textarea' ? 'textarea' : 'input');
                input.name = fd.name;
                input.value = fd.value || '';
                input.placeholder = fd.placeholder || '';
                if (fd.type && fd.type !== 'textarea') input.type = fd.type;
                l.appendChild(input);
                f.appendChild(l);
            }
            const row = document.createElement('div');
            row.className = 'row';
            row.innerHTML = `<button type="button" class="btn">Cancel</button>
                             <button type="submit" class="btn primary">${ERM.esc(submitLabel || 'OK')}</button>`;
            f.appendChild(row);
            modalBox.appendChild(f);

            const done = v => { modal._cancel = null; closeModal(); resolve(v); };
            row.firstElementChild.addEventListener('click', () => done(null));
            f.addEventListener('submit', e => {
                e.preventDefault();
                const out = {};
                for (const fd of fields) out[fd.name] = f.elements[fd.name].value.trim();
                done(out);
            });
            modal._cancel = () => resolve(null);
            modal.hidden = false;
            const first = f.querySelector('input, textarea');
            first && first.focus();
        });
    }

    function closeModal() {
        if (modal.hidden) return;
        modal.hidden = true;
        const c = modal._cancel;
        modal._cancel = null;
        c && c();
    }

    modal.addEventListener('mousedown', e => { if (e.target === modal) closeModal(); });

    ERM.ui = { openMenu, closeMenu, showTip, moveTip, hideTip, updateTip, form, closeModal };
})();
