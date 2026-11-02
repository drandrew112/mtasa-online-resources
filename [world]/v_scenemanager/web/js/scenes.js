// Scene Manager web console: browse the scene files, spawn a scene, watch / remove live ones, flag broken scenes
// and work through the reported issues. Login + admin level are checked by v_scenemanager (server/web.lua).
// English / Hungarian: the texts come from vsmWebTexts(lang) (v_locals), the choice is kept in this browser.
(function () {
    'use strict';

    const $ = id => document.getElementById(id);
    const api = OSA.api();
    const esc = OSA.esc;
    const SHOW_MAX = 300;
    const LANG_KEY = 'vsm.lang';

    const S = {
        token: null, scenes: [], live: [], auto: false, timer: null, busy: new Set(),
        lang: 'en', langs: ['en', 'hu'], texts: {}, flagOpen: null, flagError: null, flagExisting: null,
        tab: 'live', issueStatus: 'open', issues: [], issueCounts: { open: 0, resolved: 0 }, confirmClear: false,
    };

    const call = (fn, ...args) => api.call(fn, S.token, ...args);

    // text of a short key (server/web.lua WEB_KEYS) with {name} params
    function T(key, params) {
        let s = S.texts[key] || key;
        if (params) s = s.replace(/\{(\w+)(\|[^}]*)?\}/g, (m, k) => (params[k] !== undefined ? String(params[k]) : m));
        return s;
    }

    function storedLang() {
        try { return localStorage.getItem(LANG_KEY); } catch (e) { return null; }
    }

    function storeLang(lang) {
        try { localStorage.setItem(LANG_KEY, lang); } catch (e) { /* private mode */ }
    }

    function guessLang() {
        const saved = storedLang();
        if (saved) return saved;
        return (navigator.language || '').toLowerCase().startsWith('hu') ? 'hu' : 'en';
    }

    async function loadTexts(lang) {
        try {
            const r = await api.call('vsmWebTexts', lang);
            if (r && r.ok) {
                S.lang = r.lang;
                S.langs = OSA.arr(r.langs);
                S.texts = r.texts || {};
            }
        } catch (e) { /* keep the built-in English texts */ }
        document.documentElement.lang = S.lang;
        document.querySelectorAll('[data-t]').forEach(el => { el.textContent = T(el.dataset.t); });
        document.querySelectorAll('[data-tp]').forEach(el => { el.placeholder = T(el.dataset.tp); });
        renderLangs();
    }

    function renderLangs() {
        const html = S.langs.map(l => `<button type="button" data-lang="${esc(l)}" class="${l === S.lang ? 'on' : ''}">${esc(l.toUpperCase())}</button>`).join('');
        $('loginLang').innerHTML = html;
        $('topLang').innerHTML = html;
    }

    async function setLang(lang) {
        storeLang(lang);
        await loadTexts(lang);
        if (S.token) {
            fillFilters();
            renderCatalog();
            renderLive();
            renderIssues();
            updateTop();
        }
    }

    document.addEventListener('click', e => {
        const b = e.target.closest('[data-lang]');
        if (b) setLang(b.dataset.lang);
    });

    async function act(fn, ...args) {
        try {
            const r = await call(fn, ...args);
            if (r && r.error === 'unauthorized') { location.reload(); return null; }
            if (!r || r.ok === false) { OSA.toast((r && r.error) || T('request_failed')); return null; }
            return r;
        } catch (e) {
            OSA.toast(T('unreachable') + ' ' + e.message);
            return null;
        }
    }

    const dateText = ts => {
        if (!ts) return '';
        const d = new Date(ts * 1000);
        const p = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
    };

    /* ---------------------------------------------------------------- login */

    $('user').focus();
    $('loginForm').addEventListener('submit', async e => {
        e.preventDefault();
        const user = $('user').value.trim(), pass = $('pass').value;
        if (!user || !pass) return;
        $('loginBtn').disabled = true;
        $('loginError').textContent = '';
        try {
            const r = await api.call('vsmWebLogin', null, user, pass, S.lang);
            if (r && r.ok) {
                S.token = r.token;
                $('pass').value = '';
                $('who').textContent = r.name || r.account;
                document.body.classList.remove('locked');
                $('login').style.display = 'none';
                if (!storedLang() && r.lang && r.lang !== S.lang) await loadTexts(r.lang);
                start();
            } else {
                $('loginError').textContent = (r && r.error) || T('login_failed');
                $('pass').select();
            }
        } catch (err) {
            $('loginError').textContent = T('unreachable') + ' ' + err.message;
        }
        $('loginBtn').disabled = false;
    });

    $('logout').addEventListener('click', async () => {
        try { await call('vsmWebLogout'); } catch (e) { /* ignore */ }
        location.reload();
    });

    /* ---------------------------------------------------------------- catalog */

    function fillSelect(el, allLabel, values) {
        const keep = el.value;
        el.innerHTML = `<option value="">${esc(allLabel)}</option>` +
            values.map(v => `<option value="${esc(v[0])}">${esc(v[1])}</option>`).join('');
        el.value = values.some(v => v[0] === keep) ? keep : '';
    }

    function fillFilters() {
        const uniq = key => [...new Set(S.scenes.map(s => s[key]).filter(Boolean))].sort((a, b) => a.localeCompare(b));
        fillSelect($('location'), T('all_places'), uniq('location').map(v => [v, v]));
        fillSelect($('category'), T('all_categories'), uniq('category').map(v => [v, v]));
        fillSelect($('agency'), T('all_agencies'), [['ems', T('agency_ems')], ['pd', T('agency_pd')]]);
    }

    async function loadScenes() {
        const r = await act('vsmWebScenes');
        if (!r) return;
        S.scenes = OSA.arr(r.scenes).map(a => ({
            name: a[0], location: a[1], category: a[2] || 'uncategorized', title: a[3], priority: a[4],
            peds: a[5], vehicles: a[6], enabled: a[7], interior: a[8], titleHu: a[9],
            ems: a[10], pd: a[11], safe: a[12], valid: a[13], issue: a[14] || null,
        }));
        fillFilters();
        renderCatalog();
    }

    const titleOf = s => (S.lang === 'hu' && s.titleHu) ? s.titleHu : s.title;

    function needTag(agency, need) {
        return `<span class="sm-tag ${need > 0 ? agency : 'n0'}" title="${esc(T('need_short_' + need))}">${agency.toUpperCase()} ${need}</span>`;
    }

    function flagForm(s) {
        if (S.flagOpen !== s.name) return '';
        if (S.flagExisting) {
            const x = S.flagExisting;
            return `<div class="sm-flag"><div class="err">${esc(T('flag_exists'))} “${esc(x[0])}” — ${esc(x[1] || '')}, ${esc(dateText(x[2]))}</div>
                <div class="acts"><button class="osa-btn small" data-flag-cancel>${esc(T('cancel'))}</button></div></div>`;
        }
        return `<div class="sm-flag">
            <div class="title">${esc(T('flag_title', { name: s.name }))}</div>
            <textarea id="flagText" maxlength="200" placeholder="${esc(T('flag_placeholder'))}"></textarea>
            ${S.flagError ? `<div class="err">${esc(S.flagError)}</div>` : ''}
            <div class="foot"><span id="flagCount">0 / 200</span>
                <span class="acts"><button class="osa-btn small" data-flag-cancel>${esc(T('cancel'))}</button>
                <button class="osa-btn small primary" data-flag-send="${esc(s.name)}">${esc(T('flag_send'))}</button></span></div>
        </div>`;
    }

    function renderCatalog() {
        const q = $('search').value.trim().toLowerCase();
        const loc = $('location').value, cat = $('category').value, agency = $('agency').value;
        const issuesOnly = $('hasIssues').checked;
        const active = new Set(S.live.map(s => s.name));
        const hits = S.scenes.filter(s =>
            (!loc || s.location === loc) && (!cat || s.category === cat) &&
            (!agency || s[agency] > 0) && (!issuesOnly || s.issue) &&
            (!q || (s.name + ' ' + s.title + ' ' + s.titleHu + ' ' + s.location).toLowerCase().includes(q)));
        const shown = hits.slice(0, SHOW_MAX);
        $('count').textContent = T('scenes_count', { count: hits.length }) + (hits.length > SHOW_MAX ? ' - ' + T('scenes_more', { max: SHOW_MAX }) : '');
        $('catalog').innerHTML = shown.map(s => {
            const on = active.has(s.name);
            return `<div class="sm-row${s.enabled ? '' : ' off'}${on ? ' active' : ''}">
                <div class="main">
                    <div class="name">${esc(s.name)}</div>
                    <div class="sub">${esc(titleOf(s))}${s.interior ? ' (' + esc(T('interior')) + ')' : ''}</div>
                </div>
                <div class="meta">${esc(s.location)}${s.category ? ' / ' + esc(s.category) : ''}<br>P${s.priority} - ${esc(T('ped_veh', { peds: s.peds, vehicles: s.vehicles }))}</div>
                <div class="tags">${needTag('ems', s.ems)}${needTag('pd', s.pd)}
                    ${s.safe ? '' : `<span class="sm-tag unsafe">${esc(T('not_safe'))}</span>`}
                    ${s.valid ? '' : `<span class="sm-tag invalid">${esc(T('invalid'))}</span>`}
                    ${s.issue ? `<span class="sm-tag flag" title="${esc(s.issue[0])}">⚑ ${esc(T('flagged'))}</span>` : ''}</div>
                <button class="osa-btn small" data-flag="${esc(s.name)}">${esc(T('flag'))}</button>
                <button class="osa-btn small primary" data-spawn="${esc(s.name)}"${on || S.busy.has(s.name) ? ' disabled' : ''}>${esc(on ? T('active') : T('spawn'))}</button>
            </div>${flagForm(s)}`;
        }).join('') || `<div class="osa-empty">${esc(T('no_match'))}</div>`;
        const ta = $('flagText');
        if (ta) {
            ta.addEventListener('input', () => { $('flagCount').textContent = ta.value.length + ' / 200'; });
            ta.focus();
        }
    }

    ['search', 'location', 'category', 'agency', 'hasIssues'].forEach(id => $(id).addEventListener('input', renderCatalog));

    async function sendFlag(name) {
        const text = ($('flagText') && $('flagText').value || '').trim();
        const r = await call('vsmWebFlag', name, text, S.lang).catch(() => null);
        if (r && r.ok) {
            S.flagOpen = null; S.flagError = null; S.flagExisting = null;
            OSA.toast(T('flag_saved', { name }), true);
            await loadScenes();
            await loadIssues();
            return;
        }
        if (r && r.error === 'unauthorized') { location.reload(); return; }
        S.flagError = (r && r.error) || T('request_failed');
        S.flagExisting = r && r.existing ? OSA.arr(r.existing) : null;
        renderCatalog();
    }

    $('catalog').addEventListener('click', async e => {
        const flag = e.target.closest('[data-flag]');
        if (flag) {
            const s = S.scenes.find(x => x.name === flag.dataset.flag);
            S.flagOpen = S.flagOpen === flag.dataset.flag ? null : flag.dataset.flag;
            S.flagError = null;
            S.flagExisting = s && s.issue ? s.issue : null;
            renderCatalog();
            return;
        }
        if (e.target.closest('[data-flag-cancel]')) {
            S.flagOpen = null; S.flagError = null; S.flagExisting = null;
            renderCatalog();
            return;
        }
        const send = e.target.closest('[data-flag-send]');
        if (send) { await sendFlag(send.dataset.flagSend); return; }
        const btn = e.target.closest('[data-spawn]');
        if (!btn) return;
        const name = btn.dataset.spawn;
        S.busy.add(name);
        renderCatalog();
        const r = await act('vsmWebSpawn', name);
        S.busy.delete(name);
        if (r) OSA.toast(T('spawned', { name }) + (r.warning ? ' (' + r.warning + ')' : ''), true);
        await refresh();
    });

    /* ---------------------------------------------------------------- live */

    const mmss = sec => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;

    function renderLive() {
        $('clearAll').disabled = !S.live.length;
        $('clearConfirm').hidden = !S.confirmClear;
        $('live').innerHTML = S.live.map(s => {
            const tasks = s.tasks || {};
            const title = (S.lang === 'hu' && s.titleHu) ? s.titleHu : s.title;
            const late = OSA.arr(s.late);
            return `<div class="sm-card">
            <div class="head">
                <div><strong>#${s.id} ${esc(s.name)}</strong><div class="sub osa-muted">${esc(title)}</div></div>
                <span><button class="osa-btn small" data-flag-live="${esc(s.name)}">${esc(T('flag'))}</button>
                <button class="osa-btn small danger" data-remove="${s.id}">${esc(T('remove'))}</button></span>
            </div>
            <div class="tags">
                ${tasks.ems ? `<span class="sm-tag ems">EMS #${tasks.ems.id} · ${esc(T('status_' + (s.taskStatus || 'closed')))}${s.units ? ' · ' + esc(T('units', { count: s.units })) : ''}</span>` : ''}
                ${tasks.pd ? `<span class="sm-tag pd">PD #${tasks.pd.id} · ${esc(T('status_' + (s.callStatus || 'closed')))}${s.callUnits ? ' · ' + esc(T('units', { count: s.callUnits })) : ''}</span>` : ''}
                ${late.map(a => `<span class="sm-tag n0">${esc(a.toUpperCase())} · ${esc(T('late'))}</span>`).join('')}
                ${s.safety === 'unsafe' ? `<span class="sm-tag unsafe">${esc(T('not_safe'))}</span>` : s.safety === 'safe' ? `<span class="sm-tag ems">${esc(T('safe'))}</span>` : ''}
                ${s.closed ? `<span class="osa-pill">${esc(T('task_closed'))}</span>` : ''}
                <span class="osa-pill">${esc(T('patients', { count: s.patients || 0 }))}</span>
                <span class="osa-pill">${mmss(s.ageSec)}</span>
                <span class="osa-pill">${esc(s.source)}</span>
            </div>
        </div>`;
        }).join('') || `<div class="osa-empty">${esc(T('no_active'))}</div>`;
        $('liveInfo').textContent = '';
    }

    $('live').addEventListener('click', async e => {
        const flag = e.target.closest('[data-flag-live]');
        if (flag) {
            const name = flag.dataset.flagLive;
            const s = S.scenes.find(x => x.name === name);
            S.flagOpen = name; S.flagError = null; S.flagExisting = s && s.issue ? s.issue : null;
            $('search').value = name;
            renderCatalog();
            return;
        }
        const btn = e.target.closest('[data-remove]');
        if (!btn) return;
        if (await act('vsmWebRemove', Number(btn.dataset.remove))) await refresh();
    });

    $('clearAll').addEventListener('click', () => { S.confirmClear = true; renderLive(); });
    $('clearNo').addEventListener('click', () => { S.confirmClear = false; renderLive(); });
    $('clearYes').addEventListener('click', async () => {
        S.confirmClear = false;
        if (await act('vsmWebRemove', 'all')) await refresh();
    });

    $('autoBtn').addEventListener('click', async () => {
        if (await act('vsmWebAuto', !S.auto)) await refresh();
    });

    /* ---------------------------------------------------------------- issues */

    function setTab(tab) {
        S.tab = tab;
        $('tabLive').classList.toggle('on', tab === 'live');
        $('tabIssues').classList.toggle('on', tab === 'issues');
        $('livePane').hidden = tab !== 'live';
        $('issuesPane').hidden = tab !== 'issues';
        if (tab === 'issues') loadIssues();
    }

    $('tabLive').addEventListener('click', () => setTab('live'));
    $('tabIssues').addEventListener('click', () => setTab('issues'));
    $('issuesOpen').addEventListener('click', () => { S.issueStatus = 'open'; loadIssues(); });
    $('issuesResolved').addEventListener('click', () => { S.issueStatus = 'resolved'; loadIssues(); });

    async function loadIssues() {
        const r = await act('vsmWebIssues', S.issueStatus);
        if (!r) return;
        S.issues = OSA.arr(r.issues);
        S.issueCounts = { open: r.open || 0, resolved: r.resolved || 0 };
        renderIssues();
    }

    function renderIssues() {
        $('issuesOpen').classList.toggle('on', S.issueStatus === 'open');
        $('issuesResolved').classList.toggle('on', S.issueStatus === 'resolved');
        $('issuesOpen').textContent = T('open') + ' (' + S.issueCounts.open + ')';
        $('issuesResolved').textContent = T('resolved') + ' (' + S.issueCounts.resolved + ')';
        $('issues').innerHTML = S.issues.map(i => `<div class="sm-issue">
            <div class="h"><b>${esc(i.scene)}</b><span class="sm-tag flag">${esc(T('source_' + i.source))}</span></div>
            <div class="c">${esc(i.comment)}</div>
            <div class="m">${esc(T('issue_meta', { by: i.byName || '?', at: dateText(i.at) }))}${i.instance ? ' · ' + esc(T('instance', { id: i.instance })) : ''}
                ${i.status === 'resolved' ? ' · ' + esc(T('resolved_by', { by: i.resolvedBy || '?', at: dateText(i.resolvedAt) })) : ''}</div>
            <div class="acts">
                ${i.status === 'open' ? `<button class="osa-btn small on" data-resolve="${i.id}">${esc(T('resolve'))}</button>` : ''}
                <button class="osa-btn small" data-copy="${esc(i.scene)}">${esc(T('copy_name'))}</button>
            </div>
        </div>`).join('') || `<div class="osa-empty">${esc(T('no_issues'))}</div>`;
    }

    $('issues').addEventListener('click', async e => {
        const res = e.target.closest('[data-resolve]');
        if (res) {
            if (await act('vsmWebResolveIssue', Number(res.dataset.resolve))) { await loadIssues(); await loadScenes(); }
            return;
        }
        const copy = e.target.closest('[data-copy]');
        if (copy) {
            const name = copy.dataset.copy;
            try { await navigator.clipboard.writeText(name); OSA.toast(T('copied', { name }), true); }
            catch (err) { $('search').value = name; renderCatalog(); }
        }
    });

    /* ---------------------------------------------------------------- polling */

    function updateTop() {
        $('autoBtn').textContent = S.auto ? T('auto_on') : T('auto_off');
        $('autoBtn').classList.toggle('on', S.auto);
        $('issueCount').textContent = S.issueCounts.open ? String(S.issueCounts.open) : '';
    }

    async function refresh() {
        let r;
        try { r = await call('vsmWebState'); } catch (e) { $('conn').className = 'osa-conn bad'; return; }
        if (!r || r.ok === false) {
            if (r && r.error === 'unauthorized') location.reload();
            $('conn').className = 'osa-conn bad';
            return;
        }
        $('conn').className = 'osa-conn ok';
        S.live = OSA.arr(r.scenes);
        S.auto = !!r.auto;
        S.issueCounts.open = r.issues || 0;
        $('stats').textContent = r.erm ? T('stats', { active: S.live.length, ems: r.free, pd: r.freePd || 0 }) : T('erm_down');
        updateTop();
        renderLive();
        if (!S.flagOpen) renderCatalog();
    }

    async function start() {
        await loadScenes();
        await refresh();
        S.timer = setInterval(refresh, 3000);
    }

    loadTexts(guessLang());
})();
