    /* ====================================================================== dropdowns */

    // The native <select> popup is a separate OS window that an offscreen (CEF in game) page
    // never shows, so every select.osa-select is replaced by a button + list drawn in the page.
    // The <select> stays in the DOM (hidden): value / onchange / innerHTML keep working.
    let openDd = null;
    function closeDd() {
        if (!openDd) return;
        openDd.list.remove();
        openDd.btn.classList.remove('open');
        openDd = null;
    }
    function enhanceSelect(sel) {
        if (sel._osaDd) return;
        const btn = create('button', 'osa-select osa-dd');
        btn.type = 'button';
        btn.title = sel.title || '';
        sel.style.display = 'none';
        sel.parentNode.insertBefore(btn, sel.nextSibling);
        sel._osaDd = btn;
        const refresh = () => {
            const o = sel.options[sel.selectedIndex];
            btn.textContent = o ? o.textContent : '';
            btn.disabled = sel.disabled;
        };
        const desc = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value');
        Object.defineProperty(sel, 'value', {
            get() { return desc.get.call(sel); },
            set(v) { desc.set.call(sel, v); refresh(); },
        });
        new MutationObserver(refresh).observe(sel, { childList: true, subtree: true, attributes: true });
        sel.addEventListener('change', refresh);
        refresh();

        btn.addEventListener('click', e => {
            e.stopPropagation();
            if (openDd && openDd.btn === btn) return closeDd();
            closeDd();
            const list = create('div', 'osa-dd-list');
            const addOpt = (o, parent) => {
                const it = create('div', 'osa-dd-item' + (o.selected ? ' sel' : '') + (o.disabled ? ' off' : ''), o.textContent);
                if (!o.disabled) it.addEventListener('click', ev => {
                    ev.stopPropagation();
                    sel.value = o.value;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                    closeDd();
                });
                parent.appendChild(it);
            };
            Array.from(sel.children).forEach(c => {
                if (c.tagName === 'OPTGROUP') {
                    list.appendChild(create('div', 'osa-dd-group', c.label));
                    Array.from(c.children).forEach(o => addOpt(o, list));
                } else addOpt(c, list);
            });
            document.body.appendChild(list);
            const r = btn.getBoundingClientRect();
            const below = window.innerHeight - r.bottom, above = r.top;
            const up = below < 180 && above > below;
            list.style.left = r.left + 'px';
            list.style.minWidth = r.width + 'px';
            list.style.maxHeight = Math.max(120, Math.min(320, (up ? above : below) - 12)) + 'px';
            if (up) list.style.bottom = (window.innerHeight - r.top + 2) + 'px';
            else list.style.top = (r.bottom + 2) + 'px';
            btn.classList.add('open');
            openDd = { btn, list };
            const cur = list.querySelector('.sel');
            if (cur) cur.scrollIntoView({ block: 'nearest' });
        });
    }
    document.addEventListener('click', e => { if (openDd && !openDd.list.contains(e.target)) closeDd(); });
    window.addEventListener('resize', closeDd);
    OSA.ready(() => {
        const scan = () => document.querySelectorAll('select.osa-select').forEach(enhanceSelect);
        scan();
        new MutationObserver(scan).observe(document.body, { childList: true, subtree: true });
    });
