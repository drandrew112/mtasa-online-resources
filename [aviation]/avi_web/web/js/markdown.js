/* Small Markdown renderer for the documents of sanandreascontrol.eu.
   Supports: # - #### headings (with ids for the table of contents), paragraphs, **bold**, *italic*,
   `code`, ---, > notes, - / 1. lists with one nested level, | tables |,
   links: [text](doc:<id>) / [text](doc:<id>#<heading-id>) = another document (in-page, data-go),
          [text](#<heading-id>) = this document, [text](https://...) = new window,
   figures: a line ![caption](img/<file>) = an image with its caption. An .svg is left as a
          placeholder (data-svg) that the page fills in, the others are <img>. */
(function () {
    'use strict';

    const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

    function inline(s) {
        s = esc(s);
        s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
        s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        s = s.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>');
        s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, t, href) => {
            let d = href.match(/^doc:([\w-]+)(?:#([\w-]+))?$/);
            if (d) return `<a class="doc-ref" data-go="docs/${d[1]}${d[2] ? '/' + d[2] : ''}">${t}</a>`;
            if (/^#[\w-]+$/.test(href)) return `<a data-anchor="${href.slice(1)}">${t}</a>`;
            if (/^https?:\/\//.test(href)) return `<a href="${href}" target="_blank" rel="noopener">${t}</a>`;
            return t;
        });
        return s;
    }

    function slug(text, used) {
        let base = text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'sec';
        let id = base, n = 2;
        while (used.has(id)) id = base + '-' + n++;
        used.add(id);
        return id;
    }

    const cells = line => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
    const listItem = line => line.match(/^(\s*)([-*]|\d+\.)\s+(.*)$/);

    // returns { html, toc: [{ level, id, text }] }
    function render(md) {
        const lines = String(md || '').replace(/\r\n?/g, '\n').split('\n');
        const out = [], toc = [], used = new Set();
        let i = 0;

        while (i < lines.length) {
            const line = lines[i];
            if (!line.trim()) { i++; continue; }

            let m = line.match(/^(#{1,4})\s+(.*)$/);
            if (m) {
                const level = m[1].length, html = inline(m[2]);
                const id = slug(m[2], used);
                if (level >= 2 && level <= 3) toc.push({ level, id, text: html.replace(/<[^>]+>/g, '') });
                out.push(`<h${level} id="${id}">${html}</h${level}>`);
                i++; continue;
            }
            if (/^\s*(---|\*\*\*)\s*$/.test(line)) { out.push('<hr>'); i++; continue; }

            m = line.match(/^\s*!\[([^\]]*)\]\((img\/[\w.-]+)\)\s*$/);
            if (m) {
                const cap = inline(m[1]), src = m[2];
                const media = /\.svg$/i.test(src)
                    ? `<div class="md-svg" data-svg="${src.slice(4)}"></div>`
                    : `<img src="${src}" alt="${esc(m[1])}">`;
                out.push(`<figure class="md-fig">${media}${cap ? `<figcaption>${cap}</figcaption>` : ''}</figure>`);
                i++; continue;
            }

            if (/^\s*>/.test(line)) {
                const buf = [];
                while (i < lines.length && /^\s*>/.test(lines[i])) buf.push(lines[i++].replace(/^\s*>\s?/, ''));
                out.push(`<blockquote>${inline(buf.join(' '))}</blockquote>`);
                continue;
            }

            if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1])) {
                const head = cells(line);
                i += 2;
                const rows = [];
                while (i < lines.length && /^\s*\|/.test(lines[i])) rows.push(cells(lines[i++]));
                out.push('<div class="md-table"><table><thead><tr>' + head.map(h => `<th>${inline(h)}</th>`).join('') +
                    '</tr></thead><tbody>' + rows.map(r => '<tr>' + r.map(c => `<td>${inline(c)}</td>`).join('') + '</tr>').join('') +
                    '</tbody></table></div>');
                continue;
            }

            if (listItem(line)) {
                const first = listItem(line);
                const ordered = /\d/.test(first[2]);
                const indent = first[1].length;
                const items = [];
                while (i < lines.length) {
                    const l = lines[i];
                    const li = listItem(l);
                    if (li && li[1].length <= indent) {
                        items.push({ text: li[3], sub: [], subOrdered: false });
                        i++;
                    } else if (li && items.length) {
                        const it = items[items.length - 1];
                        if (!it.sub.length) it.subOrdered = /\d/.test(li[2]);
                        it.sub.push(li[3]);
                        i++;
                    } else if (l.trim() && /^\s{2,}\S/.test(l) && items.length) {
                        // continuation line of the last item (or of its last sub item)
                        const it = items[items.length - 1];
                        if (it.sub.length) it.sub[it.sub.length - 1] += ' ' + l.trim();
                        else it.text += ' ' + l.trim();
                        i++;
                    } else break;
                }
                const tag = ordered ? 'ol' : 'ul';
                out.push(`<${tag}>` + items.map(it => {
                    let s = '<li>' + inline(it.text);
                    if (it.sub.length) {
                        const st = it.subOrdered ? 'ol' : 'ul';
                        s += `<${st}>` + it.sub.map(x => `<li>${inline(x)}</li>`).join('') + `</${st}>`;
                    }
                    return s + '</li>';
                }).join('') + `</${tag}>`);
                continue;
            }

            // paragraph: up to the next blank line / block
            const buf = [];
            while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|\s*>|\s*\||\s*([-*]|\d+\.)\s|\s*---\s*$|\s*!\[)/.test(lines[i])) {
                buf.push(lines[i++].trim());
            }
            if (!buf.length) buf.push(lines[i++].trim());
            out.push(`<p>${inline(buf.join(' '))}</p>`);
        }
        return { html: out.join('\n'), toc };
    }

    window.SacMarkdown = { render };
})();
