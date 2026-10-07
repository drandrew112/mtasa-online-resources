// Dispatcher chat: broadcast, per-unit threads and per-task (all assigned units).
(function () {
    'use strict';

    const sel = document.getElementById('chatChannel');
    const log = document.getElementById('chatLog');
    const form = document.getElementById('chatForm');
    const input = document.getElementById('chatText');

    const messages = [];
    const seen = {};              // channel key -> last read message id
    let lastId = 0;
    let current = 'broadcast';
    let optionSig = '';
    let channelList = [];

    const keyOf = m => m.channel === 'broadcast' ? 'broadcast' : m.channel + ':' + m.target;

    function unread(key) {
        const since = seen[key] || 0;
        return messages.filter(m => !m.fromDispatch && m.id > since && keyOf(m) === key).length;
    }

    // quiet: initial history load, no toasts
    function add(list, quiet) {
        if (!list.length) return;
        for (const m of list) {
            messages.push(m);
            lastId = Math.max(lastId, m.id);
            if (quiet) seen[keyOf(m)] = m.id;
            if (!quiet && !m.fromDispatch && keyOf(m) !== current) {
                ERM.toast(`${ERM.clean(m.from)}: ${m.text}`, true);
            }
        }
        while (messages.length > 1000) messages.shift();
        rebuildOptions(true);
        render();
    }

    // units / tasks -> selectable channels
    function setChannels(units, tasks) {
        channelList = [{ key: 'broadcast', label: 'Broadcast (all units)' }];
        for (const u of units) channelList.push({ key: 'unit:' + u.id, label: `Unit ${u.callsign}` });
        for (const t of tasks) {
            if (t.units.length) channelList.push({ key: 'task:' + t.id, label: `Case #${t.id} (${t.units.length} units)` });
        }
        if (!channelList.some(c => c.key === current)) {
            channelList.push({ key: current, label: current.replace(':', ' #') + ' (offline)' });
        }
        rebuildOptions();
    }

    function rebuildOptions(force) {
        const opts = channelList.map(c => {
            const n = c.key === current ? 0 : unread(c.key);
            return { key: c.key, text: c.label + (n ? ` • ${n} new` : '') };
        });
        const sig = opts.map(o => o.key + o.text).join('|');
        if (sig === optionSig && !force) return;
        optionSig = sig;
        sel.innerHTML = opts.map(o => `<option value="${o.key}">${ERM.esc(o.text)}</option>`).join('');
        sel.value = current;
    }

    function render() {
        const list = messages.filter(m => keyOf(m) === current);
        const nearBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 40;
        if (!list.length) {
            log.innerHTML = '<div class="osa-empty">No messages in this channel.</div>';
        } else {
            log.innerHTML = list.map(m => `
                <div class="msg${m.fromDispatch ? '' : ' incoming'}">
                    <div class="msg-head">
                        <span class="msg-tag tag-${m.channel}">${ERM.esc(m.channel === 'task' ? m.label : m.channel === 'broadcast' ? 'BROADCAST' : m.label)}</span>
                        <b>${ERM.esc(ERM.clean(m.from))}</b>
                        <time>${ERM.esc(m.time)}</time>
                    </div>
                    <div class="msg-text">${ERM.esc(m.text)}</div>
                </div>`).join('');
            seen[current] = list[list.length - 1].id;
        }
        if (nearBottom) log.scrollTop = log.scrollHeight;
    }

    function open(key) {
        current = key;
        if (!channelList.some(c => c.key === key)) channelList.push({ key, label: key });
        rebuildOptions(true);
        render();
        log.scrollTop = log.scrollHeight;
        input.focus();
    }

    sel.addEventListener('change', () => open(sel.value));

    form.addEventListener('submit', async e => {
        e.preventDefault();
        const text = input.value.trim();
        if (!text) return;
        const [channel, target] = current.split(':');
        const r = await ERM.act('ermSendMessage', channel, Number(target) || 0, text);
        if (r) input.value = '';
    });

    ERM.chat = {
        add,
        setChannels,
        open,
        lastId: () => lastId,
    };
})();
