// Shared by every med_web page: links between the pages. Over HTTP a page is /med_web/<name>.html
// (the landing page is /med_web/); in game every page is opened through web_api's loader, so
// the link keeps the loader and swaps its ?page=.
(function () {
    'use strict';

    const MedWeb = window.MedWeb = {};

    MedWeb.pageUrl = function (name) {
        if (OSA.inGame) {
            const q = new URLSearchParams(location.search);
            q.set('page', 'web/' + name + '.html');
            return location.pathname + '?' + q.toString();
        }
        return name === 'index' ? '/med_web/' : '/med_web/' + name + '.html';
    };

    MedWeb.go = name => { location.href = MedWeb.pageUrl(name); };

    // <a data-goto="dispatch"> -> the right url in both modes
    function wire() {
        document.querySelectorAll('a[data-goto]').forEach(a => { a.href = MedWeb.pageUrl(a.dataset.goto); });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', wire);
    else wire();
})();
