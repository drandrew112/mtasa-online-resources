// Home: the three public counters.
(function () {
    'use strict';
    const { $ } = BT;
    const fmt = n => Number(n || 0).toLocaleString('en-US');
    BT.on(s => {
        if (!s) return;
        $('stOnDuty').textContent = fmt(s.onDuty);
        $('stActive').textContent = fmt(s.active);
        $('stDone').textContent = fmt(s.completed);
    });
})();
