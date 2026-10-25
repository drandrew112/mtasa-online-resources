// gov_news - the News page of /gov (see gov_core web/js/gov.js GOV.page).
(function () {
    'use strict';
    const { esc, arr, stamp, head, empty, btn } = GOV.ui;
    const T = GOV.tr('gov_news');
    const D = GOV.D, sel = GOV.sel;

    GOV.page('news', {
        keys: GOV.keys('gov_news', ['new_news', 'news_title', 'news_body', 'news_send', 'news_hint', 'news_not_mailed', 'confirm_delete_news']),
        render(d) {
            const m = GOV.can('news.post'), del = GOV.can('news.delete');
            const langs = arr(d.langs);
            const card = n => {
                const texts = n.texts || {};
                const codes = [...langs.map(l => l.value).filter(c => texts[c]), ...Object.keys(texts).filter(c => !langs.some(l => l.value === c))];
                return `<div class="gv-card"><div class="gv-head"><div><div class="gv-sub">${stamp(n.createdAt)} · ${esc(n.createdBy)}` +
                    `${n.mailed ? '' : ` <span class="tag bad">${esc(T('news_not_mailed'))}</span>`}</div></div>` +
                    (del ? `<div class="gv-row">${btn(T('delete'), 'deleteNews', { id: n.id }, 'danger')}</div>` : '') + '</div>' +
                    codes.map(c => `<div style="margin-top:10px"><span class="tag">${esc(c.toUpperCase())}</span> <b>${esc(texts[c].title)}</b>` +
                        `<p class="gv-desc">${esc(texts[c].body)}</p></div>`).join('') + '</div>';
            };
            return head(GOV.title('news'), esc(T('news_hint')), m ? btn(T('new_news'), 'newNews', {}, 'primary') : '') +
                (arr(d.list).map(card).join('') || empty());
        },
        actions: {
            async newNews() {
                const langs = arr((D.news || {}).langs);
                const draft = sel.newsDraft || {};
                const fields = [];
                for (const l of langs) {
                    fields.push({ name: 'title_' + l.value, label: T('news_title') + ' (' + l.label + ')', value: draft['title_' + l.value] });
                    fields.push({ name: 'body_' + l.value, label: T('news_body') + ' (' + l.label + ')', type: 'textarea', value: draft['body_' + l.value] });
                }
                const r = await OSA.ui.form(T('new_news'), fields, T('news_send'), T('news_hint'));
                if (!r) return;
                sel.newsDraft = r;   // kept when the server refuses it
                const texts = {};
                for (const l of langs) texts[l.value] = { title: r['title_' + l.value], body: r['body_' + l.value] };
                if (await GOV.change('postNews', { texts })) sel.newsDraft = null;
            },
            async deleteNews(b) { if (await OSA.ui.confirm(T('delete'), T('confirm_delete_news'), T('delete'))) GOV.change('deleteNews', { id: Number(b.dataset.id) }); },
        },
    });
})();
