    /* ====================================================================== poll */

    // Runs fn() now and then every `ms` after it finished (never overlapping).
    // opts: onOk(), onFail(consecutiveFailures, error). Returns { stop(), now() }.
    OSA.poll = function (fn, ms, opts) {
        opts = opts || {};
        let timer = null, stopped = false, running = false, again = false, fails = 0;
        async function run() {
            if (running) { again = true; return; }
            running = true;
            clearTimeout(timer);
            try {
                await fn();
                fails = 0;
                if (opts.onOk) opts.onOk();
            } catch (e) {
                fails++;
                if (opts.onFail) opts.onFail(fails, e);
            }
            running = false;
            if (stopped) return;
            if (again) { again = false; return run(); }
            timer = setTimeout(run, typeof ms === 'function' ? ms() : ms);
        }
        run();
        return { stop() { stopped = true; clearTimeout(timer); }, now: run };
    };
