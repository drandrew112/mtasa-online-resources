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
