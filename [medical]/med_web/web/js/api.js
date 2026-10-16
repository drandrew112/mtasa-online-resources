// ERM facade over the shared web_api toolkit (OSA): API calls with the session token, the
// helpers and overlays the dispatcher console uses, and its status texts.
(function () {
    'use strict';

    const api = OSA.api();

    const ERM = window.ERM = {
        token: null,       // session token, memory only (reload = login again)
        inGame: OSA.inGame,
        call: (fn, ...args) => api.call(fn, ERM.token, ...args),

        arr: OSA.arr,
        esc: OSA.esc,
        clean: OSA.clean,
        clock: OSA.clock,
        age: OSA.age,
        now: () => OSA.time.now(),
        toast: OSA.toast,
        ui: OSA.ui,
    };

    ERM.STATUS = {
        available: 'Available',
        enroute: 'En Route',
        onscene: 'On Scene',
        handover: 'Handover',
    };

    ERM.TASK_STATUS = {
        unassigned: 'Not assigned',
        prioritized: 'Prioritized',
        assigned: 'Assigned',
        closed: 'Closed',
    };

    // Runs an API action and reports its error, if any.
    ERM.act = async function (fn, ...args) {
        try {
            const r = await ERM.call(fn, ...args);
            if (r && r.error === 'unauthorized') {
                ERM.app.lock();
                return null;
            }
            if (!r || r.ok === false) {
                ERM.toast((r && r.error) || 'Request failed');
                return null;
            }
            if (ERM.app) ERM.app.refresh();
            return r;
        } catch (e) {
            ERM.toast('Server unreachable: ' + e.message);
            return null;
        }
    };
})();
