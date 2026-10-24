// gov_votes - the Votes page of /gov (see gov_core web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, stamp, head, empty, btn } = GOV.ui;
    const T = GOV.tr('gov_votes');

    GOV.page('votes', {
        keys: GOV.keys('gov_votes', ['votes_open', 'votes_closed', 'new_vote', 'vote_title', 'vote_description', 'vote_options',
            'vote_options_hint', 'vote_hours', 'vote_ends', 'voters_n', 'close_vote', 'cancel_vote', 'status_open', 'status_closed',
            'status_cancelled', 'results_after_close', 'winner']),
        render(d) {
            const m = GOV.can('minister');
            const list = arr(d.list);
            const now = Date.now() / 1000;
            const card = v => {
                const opts = arr(v.options);
                const res = arr(v.results);
                const total = res.reduce((t, n) => t + n, 0);
                const best = Math.max(0, ...res);
                const status = v.status === 'open' && v.endsAt <= now ? 'closed' : v.status;
                let body;
                if (v.status === 'closed') {
                    body = opts.map((o, i) => {
                        const n = res[i] || 0, p = total ? Math.round(n / total * 1000) / 10 : 0;
                        return `<div class="gv-res${n === best && n > 0 ? ' win' : ''}"><div class="gv-row" style="justify-content:space-between"><span>${esc(o)}` +
                            `${n === best && n > 0 ? ` <span class="tag state">${esc(T('winner'))}</span>` : ''}</span><span class="mono">${n} · ${p}%</span></div>` +
                            `<div class="gv-meter"><i style="width:${p}%"></i></div></div>`;
                    }).join('');
                } else {
                    body = `<ul class="gv-opts">${opts.map(o => `<li>${esc(o)}</li>`).join('')}</ul>` +
                        (v.status === 'open' ? `<div class="gv-sub">${esc(T('results_after_close'))}</div>` : '');
                }
                return `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(v.title)}</h2>` +
                    `<div class="gv-sub"><span class="tag ${status === 'open' ? 'state' : status === 'cancelled' ? 'bad' : ''}">${esc(T('status_' + status))}</span> ` +
                    `${esc(T('voters_n', { n: v.voters }))} · ${esc(T('vote_ends'))} ${stamp(v.status === 'open' ? v.endsAt : (v.closedAt || v.endsAt))} · ${esc(v.createdBy)}</div></div>` +
                    (m && v.status === 'open' ? `<div class="gv-row">${btn(T('close_vote'), 'closeVote', { id: v.id })}${btn(T('cancel_vote'), 'cancelVote', { id: v.id }, 'danger')}</div>` : '') +
                    `</div>${v.description ? `<p class="gv-desc">${esc(v.description)}</p>` : ''}${body}</div>`;
            };
            const open = list.filter(v => v.status === 'open'), done = list.filter(v => v.status !== 'open');
            return head(GOV.title('votes'), null, m ? btn(T('new_vote'), 'newVote', {}, 'primary') : '') +
                `<h2>${esc(T('votes_open'))}</h2>${open.map(card).join('') || empty()}` +
                `<h2 style="margin-top:8px">${esc(T('votes_closed'))}</h2>${done.map(card).join('') || empty()}`;
        },
        actions: {
            async newVote() {
                const r = await OSA.ui.form(T('new_vote'), [
                    { name: 'title', label: T('vote_title') },
                    { name: 'description', label: T('vote_description'), type: 'textarea' },
                    { name: 'options', label: T('vote_options'), type: 'textarea', placeholder: T('vote_options_hint') },
                    { name: 'hours', label: T('vote_hours'), type: 'number', value: '24' },
                ], T('create'));
                if (r) GOV.change('openVote', { title: r.title, description: r.description, hours: Number(r.hours),
                    options: r.options.split('\n').map(x => x.trim()).filter(Boolean) });
            },
            async closeVote(b) { if (await OSA.ui.confirm(T('close_vote'), '', T('close_vote'))) GOV.change('closeVote', { id: Number(b.dataset.id) }); },
            async cancelVote(b) { if (await OSA.ui.confirm(T('cancel_vote'), '', T('cancel_vote'))) GOV.change('cancelVote', { id: Number(b.dataset.id) }); },
        },
    });
})();
