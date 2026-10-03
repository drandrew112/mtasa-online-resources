// Persistent data cache: expensive world data (surface maps, verified spots...) is
// generated once and reused by later sessions. One JSON file per entry:
//   <cacheDir>/<kind>/<key>.json = { meta, data }
// plus <cacheDir>/index.json with the metas only (cheap listing).

import fs from 'node:fs';
import path from 'node:path';
import { ToolError } from './errors.js';

const KEY_RE = /^[a-z0-9][a-z0-9_.-]{0,99}$/;

export function cacheKey(...parts) {
  return parts.filter((p) => p !== undefined && p !== null && p !== '')
    .map((p) => String(p).toLowerCase().replace(/[^a-z0-9_.-]+/g, '_').replace(/^_+|_+$/g, ''))
    .join('.');
}

export class DataCache {
  constructor(dir) {
    this.dir = dir;
    this.indexFile = path.join(dir, 'index.json');
    this.index = null;
  }

  #load() {
    if (this.index) return this.index;
    this.index = {};
    try {
      this.index = JSON.parse(fs.readFileSync(this.indexFile, 'utf8')).entries || {};
    } catch {
      // missing / broken index: rebuild it from the entry files
      this.index = this.#rebuild();
    }
    return this.index;
  }

  #rebuild() {
    const idx = {};
    if (!fs.existsSync(this.dir)) return idx;
    for (const kind of fs.readdirSync(this.dir, { withFileTypes: true })) {
      if (!kind.isDirectory()) continue;
      for (const f of fs.readdirSync(path.join(this.dir, kind.name))) {
        if (!f.endsWith('.json')) continue;
        try {
          const e = JSON.parse(fs.readFileSync(path.join(this.dir, kind.name, f), 'utf8'));
          if (e.meta?.key) idx[e.meta.key] = e.meta;
        } catch { /* skip broken file */ }
      }
    }
    return idx;
  }

  #saveIndex() {
    fs.mkdirSync(this.dir, { recursive: true });
    fs.writeFileSync(this.indexFile, JSON.stringify({ format: 1, entries: this.index }, null, 1));
  }

  #file(kind, key) {
    return path.join(this.dir, kind, `${key}.json`);
  }

  static checkKey(key) {
    if (typeof key !== 'string' || !KEY_RE.test(key)) {
      throw new ToolError('INVALID_PARAMS', `Invalid cache key '${key}'.`, { suggestion: 'Lowercase letters, digits, "_", "-", "." (max 100 chars).' });
    }
  }

  list({ kind, prefix } = {}) {
    return Object.values(this.#load())
      .filter((m) => (!kind || m.kind === kind) && (!prefix || m.key.startsWith(prefix)))
      .sort((a, b) => a.key.localeCompare(b.key));
  }

  meta(key) {
    return this.#load()[key] || null;
  }

  has(key) {
    return !!this.meta(key);
  }

  /** -> { meta, data } or null */
  get(key) {
    const m = this.meta(key);
    if (!m) return null;
    try {
      return JSON.parse(fs.readFileSync(this.#file(m.kind, key), 'utf8'));
    } catch {
      delete this.index[key];
      this.#saveIndex();
      return null;
    }
  }

  /** Writes / replaces an entry. meta: { kind, description, params, complete, ... } */
  put(key, meta, data) {
    DataCache.checkKey(key);
    const kind = cacheKey(meta.kind || 'misc');
    const prev = this.meta(key);
    if (prev && prev.kind !== kind) fs.rmSync(this.#file(prev.kind, key), { force: true });
    const now = new Date().toISOString();
    const full = {
      ...meta, key, kind,
      createdAt: prev?.createdAt || now, updatedAt: now,
      items: Array.isArray(data) ? data.length : data && typeof data === 'object' ? Object.keys(data).length : 1,
    };
    const body = JSON.stringify({ meta: full, data });
    full.bytes = Buffer.byteLength(body);
    fs.mkdirSync(path.join(this.dir, kind), { recursive: true });
    fs.writeFileSync(this.#file(kind, key), JSON.stringify({ meta: full, data }));
    this.#load()[key] = full;
    this.#saveIndex();
    return full;
  }

  delete(key) {
    const m = this.meta(key);
    if (!m) return false;
    fs.rmSync(this.#file(m.kind, key), { force: true });
    delete this.index[key];
    this.#saveIndex();
    return true;
  }

  stats() {
    const list = this.list();
    const kinds = {};
    for (const m of list) kinds[m.kind] = (kinds[m.kind] || 0) + 1;
    return { dir: this.dir, entries: list.length, kinds, bytes: list.reduce((s, m) => s + (m.bytes || 0), 0) };
  }
}
