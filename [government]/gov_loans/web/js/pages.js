// gov_loans - the Loans page of /gov (see gov_core web/js/gov.js GOV.page).
// State loans from the bank (eco_loan kind "state"): KPIs, the open loans with early repayment,
// a new loan (state account, amount, installments; preview with the bank's terms), the closed
// loans and the payments of one loan.
(function () {
    'use strict';
    const { esc, arr, $, money, cls, stamp, val, numOf, head, kpi, empty, table, btn, select } = GOV.ui;
    const T = GOV.tr('gov_loans');
    const sel = GOV.sel;

    // the same arithmetic as eco_loan shared/calc.lua (the server checks it again)
    function quote(amount, n, rate) {
        const interest = Math.floor(amount * rate / 100 + 0.5);
        const total = amount + interest;
        return { interest, total, installment: Math.ceil(total / n) };
    }

    const statusText = s => T('eco_loan.status.' + s);
    const days = sec => Math.round((Number(sec) || 0) / 86400 * 10) / 10;

    function preview(d) {
        const lim = d.limits || {};
        const amount = Number(val('lnAmount').replace(/[^\d]/g, '')) || 0;
        const n = Number(val('lnCount')) || lim.installments || 1;
        if (!amount) return esc(T('ln_preview_empty'));
        if (amount < lim.minAmount || amount > lim.maxAmount) return `<span class="neg">${esc(T('eco_loan.error.bad_amount'))}</span>`;
        if (n < 1 || n > lim.maxInstallments) return `<span class="neg">${esc(T('eco_loan.error.bad_installments'))}</span>`;
        const q = quote(amount, n, lim.rate || 0);
        return esc(T('ln_preview', { amount: money(amount), total: money(q.total), interest: money(q.interest), n,
            installment: money(q.installment), days: days(lim.interval) }));
    }

    function paymentsCard() {
        const p = sel.lnPayments;
        if (!p) return '';
        const l = p.loan || {};
        return `<div class="gv-card"><div class="gv-head"><div><h2 style="margin:0">${esc(T('ln_payments', { id: l.id }))}</h2>` +
            `<div class="gv-sub">${esc(l.borrowerName)} · ${esc(statusText(l.status))}</div></div>${btn(T('close'), 'lnPayClose')}</div>` +
            table([[T('time')], [T('ln_payment_kind')], [T('amount'), 'r'], [T('ln_remaining'), 'r'], [T('detail')], [T('actor')]],
                arr(p.payments).map(x => `<tr><td class="mono dim">${stamp(x.ts)}</td><td>${esc(T('ln_pk_' + x.kind))}</td>` +
                    `<td class="r mono">${money(x.amount)}</td><td class="r mono dim">${money(x.remaining)}</td>` +
                    `<td class="dim">${esc(x.info || '')}</td><td><b>${esc(x.actor || '')}</b></td></tr>`)) + '</div>';
    }

    GOV.page('loans', {
        keys: [...GOV.keys('gov_loans', ['hint', 'debt', 'open_count', 'monthly', 'terms', 'ln_open', 'ln_closed', 'ln_new', 'ln_account',
            'ln_installments', 'ln_take', 'ln_preview', 'ln_preview_empty', 'ln_confirm', 'ln_borrower', 'ln_principal', 'ln_total',
            'ln_remaining', 'ln_installment', 'ln_progress', 'ln_next', 'ln_repay', 'ln_payoff', 'ln_confirm_payoff', 'ln_repay_prompt',
            'ln_details', 'ln_payments', 'ln_payment_kind', 'ln_closed_at', 'ln_status', 'ln_pk_payout', 'ln_pk_installment',
            'ln_pk_forced', 'ln_pk_extra', 'ln_pk_missed', 'ln_pk_forgive', 'ln_note']),
            ...['pending', 'active', 'paid', 'forgiven', 'failed'].map(s => 'eco_loan.status.' + s),
            'eco_loan.error.bad_amount', 'eco_loan.error.bad_installments'],
        render(d) {
            const lim = d.limits || {};
            const open = arr(d.open);
            // gov.<target>.loans: take / repay for that account (gov_perms)
            const canLoan = target => !!target && GOV.can('gov.' + target + '.loans');
            const states = arr(d.states).filter(s => s.status === 'active' && canLoan(s.target));
            const m = states.length > 0;
            const perDay = open.reduce((t, l) => t + Math.min(l.installment, l.remaining) * 86400 / (l.interval || 86400), 0);
            let h = head(GOV.title('loans'), esc(T('hint'))) +
                `<div class="gv-kpis">${kpi(T('debt'), money(d.debt), d.debt > 0 ? 'neg' : '')}${kpi(T('open_count'), String(open.length))}` +
                kpi(T('monthly'), money(perDay * 30), perDay > 0 ? 'neg' : '') + '</div>';

            h += `<div class="gv-card"><h2>${esc(T('ln_open'))}</h2>` +
                table([['#'], [T('ln_borrower')], [T('ln_principal'), 'r'], [T('ln_total'), 'r'], [T('ln_remaining'), 'r'],
                    [T('ln_installment'), 'r'], [T('ln_progress')], [T('ln_next')], [T('ln_note')], ['', 'act']],
                    open.map(l => `<tr><td class="mono dim">${l.id}</td><td>${esc(l.borrowerName)}</td><td class="r mono">${money(l.principal)}</td>` +
                        `<td class="r mono dim">${money(l.total)} (${esc(String(l.rate))}%)</td><td class="r mono neg">${money(l.remaining)}</td>` +
                        `<td class="r mono">${money(l.installment)}</td><td>${l.paidCount}/${l.installments}</td>` +
                        `<td class="mono dim">${l.status === 'active' && l.nextIn !== false ? stamp(Date.now() / 1000 + l.nextIn) : esc(statusText(l.status))}</td>` +
                        `<td class="dim">${esc(l.note || '')}</td>` +
                        `<td class="act">${btn(T('ln_details'), 'lnPay', { id: l.id })}` +
                        (canLoan(l.target) && l.status === 'active' ? ` <input class="osa-input num" id="lnR${l.id}" placeholder="${esc(T('amount'))}" data-keep="1"> ` + btn(T('ln_repay'), 'lnRepay', { id: l.id }) + ' ' + btn(T('ln_payoff'), 'lnPayoff', { id: l.id }, 'danger') : '') +
                        '</td></tr>')) + '</div>';

            h += paymentsCard();

            if (m) {
                const n = lim.installments || 30;
                h += `<div class="gv-card"><h2>${esc(T('ln_new'))}</h2>` +
                    `<div class="gv-sub" style="margin:-6px 0 10px">${esc(T('terms', { rate: lim.rate, min: money(lim.minAmount), max: money(lim.maxAmount),
                        days: days(lim.interval), maxn: lim.maxInstallments }))}</div>` +
                    `<div class="gv-row"><label class="dim">${esc(T('ln_account'))}</label>` +
                    select('lnAccount', states.map(s => [s.id, `${s.name} (${money(s.balance)})`]), states[0] && states[0].id, '', true).replace('<select ', '<select data-keep="1" ') +
                    `<input class="osa-input num" id="lnAmount" placeholder="${esc(T('amount'))}" data-keep="1">` +
                    `<label class="dim">${esc(T('ln_installments'))}</label><input class="osa-input num" id="lnCount" value="${n}" data-keep="1">` +
                    `<input class="osa-input mid" id="lnNote" placeholder="${esc(T('note'))}" maxlength="48" data-keep="1">` +
                    btn(T('ln_take'), 'lnTake', {}, 'primary') + '</div>' +
                    `<div class="gv-sub" id="lnPreview" style="margin-top:10px"></div></div>`;
            }

            h += `<div class="gv-card"><h2>${esc(T('ln_closed'))}</h2>` +
                table([['#'], [T('ln_borrower')], [T('ln_principal'), 'r'], [T('ln_total'), 'r'], [T('ln_status')], [T('ln_closed_at')], ['', 'act']],
                    arr(d.closed).map(l => `<tr><td class="mono dim">${l.id}</td><td>${esc(l.borrowerName)}</td><td class="r mono">${money(l.principal)}</td>` +
                        `<td class="r mono dim">${money(l.paidAmount)} / ${money(l.total)}</td><td>${esc(statusText(l.status))}</td>` +
                        `<td class="mono dim">${l.closedAt ? stamp(l.closedAt) : '-'}</td><td class="act">${btn(T('ln_details'), 'lnPay', { id: l.id })}</td></tr>`)) + '</div>';

            // the preview follows the typed values (no re-render while typing)
            setTimeout(() => {
                const box = $('lnPreview');
                if (!box) return;
                const upd = () => { box.innerHTML = preview(d); };
                for (const id of ['lnAmount', 'lnCount']) { const el = $(id); if (el) el.oninput = upd; }
                upd();
            }, 0);
            return h;
        },
        actions: {
            async lnTake() {
                const d = GOV.D.loans || {};
                const amount = numOf('lnAmount'), n = numOf('lnCount');
                if (amount === null || n === null) return;
                const acc = arr(d.states).find(s => String(s.id) === val('lnAccount'));
                if (!acc) return;
                const q = quote(amount, n, (d.limits || {}).rate || 0);
                if (!await OSA.ui.confirm(T('ln_new'), T('ln_confirm', { account: acc.name, amount: money(amount), total: money(q.total), n,
                    installment: money(q.installment) }), T('ln_take'))) return;
                if (await GOV.change('takeLoan', { account: acc.id, amount, installments: n, note: val('lnNote') })) {
                    for (const id of ['lnAmount', 'lnNote']) if ($(id)) $(id).value = '';
                }
            },
            async lnRepay(b) {
                const l = arr((GOV.D.loans || {}).open).find(x => x.id === Number(b.dataset.id));
                if (!l) return;
                const amount = numOf('lnR' + l.id);
                if (amount === null || amount <= 0) return;
                if (!await OSA.ui.confirm(T('ln_repay'), T('ln_repay_prompt', { id: l.id, amount: money(Math.min(amount, l.remaining)) }), T('ln_repay'))) return;
                GOV.change('repayLoan', { id: l.id, amount });
            },
            async lnPayoff(b) {
                const l = arr((GOV.D.loans || {}).open).find(x => x.id === Number(b.dataset.id));
                if (!l) return;
                if (await OSA.ui.confirm(T('ln_payoff'), T('ln_confirm_payoff', { id: l.id, amount: money(l.remaining), account: l.borrowerName }), T('ln_payoff'))) {
                    GOV.change('repayLoan', { id: l.id });
                }
            },
            async lnPay(b) {
                try {
                    sel.lnPayments = await GOV.call('loanPayments', { id: Number(b.dataset.id) });
                    GOV.render();
                } catch (e) { OSA.toast(e.message, false); }
            },
            lnPayClose() { sel.lnPayments = null; GOV.render(); },
        },
    });
})();
