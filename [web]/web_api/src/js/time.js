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
