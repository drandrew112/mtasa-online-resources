// Landing page (web/index.html): live service figures and the hospital map, from the public
// medWebPublic export (anonymous counts only).
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const { esc, arr } = OSA;
    const api = OSA.api();
    const STATUSES = ['available', 'enroute', 'onscene', 'handover'];

    const map = new OSA.Map($('map'), { maxZoom: 2 });
    let hospKey = '';

    function selectHospital(i) {
        document.querySelectorAll('#hospList li').forEach(li => li.classList.toggle('active', Number(li.dataset.i) === i));
        map.markers.forEach((m, key) => m.classList.toggle('active', key === 'h:' + i));
    }

    function renderHospitals(list) {
        const key = list.map(h => h.name).join('|');
        if (key === hospKey) return;
        hospKey = key;

        if (!list.length) {
            $('hospList').innerHTML = '<li class="osa-empty">No hospital data available.</li>';
            map.removeMissing('h:', new Set());
            return;
        }
        $('hospList').innerHTML = list.map((h, i) => `
            <li data-i="${i}">
                <span class="hosp-dot">H</span>
                <span><b>${esc(h.name)}</b><small>${h.bays} ambulance bay${h.bays === 1 ? '' : 's'}</small></span>
            </li>`).join('');
        $('hospList').querySelectorAll('li').forEach(li => li.addEventListener('click', () => {
            const i = Number(li.dataset.i);
            map.focus(list[i].x, list[i].y, 0.8);
            selectHospital(i);
        }));

        const keep = new Set();
        list.forEach((h, i) => {
            keep.add('h:' + i);
            const m = map.marker('h:' + i, h.x, h.y, 'hosp-pin', 'H', () => selectHospital(i));
            m.title = h.name;
        });
        map.removeMissing('h:', keep);
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        list.forEach(h => {
            minX = Math.min(minX, h.x); maxX = Math.max(maxX, h.x);
            minY = Math.min(minY, h.y); maxY = Math.max(maxY, h.y);
        });
        map.fitBox(minX, minY, maxX, maxY, 400);
    }

    function render(r) {
        const by = r.byStatus || {};
        $('stUnits').textContent = r.units;
        $('stAvail').textContent = by.available || 0;
        $('stTasks').textContent = r.tasks;
        $('stHosp').textContent = arr(r.hospitals).length;

        $('stBar').innerHTML = r.units
            ? STATUSES.map(s => `<i class="${s}" style="flex-grow:${by[s] || 0}"></i>`).join('')
            : '';
        $('stNote').textContent = !r.online
            ? 'The dispatch system is offline at the moment.'
            : (r.units ? 'Updated ' + new Date().toLocaleTimeString() : 'No ambulance unit is on duty right now.');
        renderHospitals(arr(r.hospitals));
    }

    OSA.poll(async () => {
        const r = await api.call('medWebPublic');
        if (r && r.ok) render(r);
    }, 5000, {
        onOk: () => { $('conn').className = 'osa-conn ok'; $('conn').title = 'Live'; },
        onFail: (n, e) => {
            $('conn').className = 'osa-conn bad';
            $('conn').title = 'Disconnected: ' + e.message;
            $('stNote').textContent = 'Live status is unavailable.';
        },
    });
})();
