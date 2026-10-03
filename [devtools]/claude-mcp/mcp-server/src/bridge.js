// HTTP client for the claude-mcp bridge resource.
//
// Request : POST /<resource>/call/<category>  body [action, params, { callback }]
// Response: [envelope]  -> { ok, result } | { ok, pending, job } | { ok: false, error }
// Pending jobs are completed by a push from the bridge (fetchRemote to the local
// callback listener) or, as a fallback, by polling jobs("poll").

import http from 'node:http';
import { config, bridgeUrl } from './config.js';
import { ToolError } from './errors.js';

export class Bridge {
  constructor() {
    this.waiters = new Map(); // job id -> { resolve, reject, timer }
    this.instanceId = null;
    this.previousInstanceId = null;
    this.restarts = 0;
    this.pendingNotice = null;
    this.lastSuccessAt = null;
    this.lastError = null;
    this.requests = 0;
    this.failures = 0;
    this.callbackUrl = null;
    this.callbackError = null;
    this.pollTimer = null;
    this.latencies = [];
  }

  async start() {
    if (!config.callbackPort) return;
    await new Promise((resolve) => {
      const server = http.createServer((req, res) => {
        if (req.method !== 'POST' || !req.url.startsWith('/job')) {
          res.writeHead(404).end();
          return;
        }
        const chunks = [];
        req.on('data', (c) => chunks.push(c));
        req.on('end', () => {
          res.writeHead(200, { 'Content-Type': 'application/json' }).end('{"ok":true}');
          try {
            let body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            if (Array.isArray(body)) body = body[0];
            if (body && body.job) this.#settle(body.job, body.envelope);
          } catch {
            /* ignore malformed pushes */
          }
        });
      });
      server.on('error', (err) => {
        this.callbackError = `callback listener disabled (${err.code || err.message}); polling only`;
        resolve();
      });
      this.server = server;
      server.listen(config.callbackPort, '127.0.0.1', () => {
        this.callbackUrl = `http://127.0.0.1:${config.callbackPort}/job`;
        server.unref();
        resolve();
      });
    });
  }

  async close() {
    if (this.pollTimer) clearInterval(this.pollTimer);
    if (this.server) await new Promise((r) => this.server.close(() => r()));
  }

  #headers() {
    const h = { 'Content-Type': 'application/json' };
    if (config.httpUser) {
      h.Authorization = 'Basic ' + Buffer.from(`${config.httpUser}:${config.httpPass}`).toString('base64');
    }
    return h;
  }

  async #post(category, body, timeoutMs = 15000) {
    const url = bridgeUrl(category);
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    let res;
    try {
      res = await fetch(url, { method: 'POST', headers: this.#headers(), body: JSON.stringify(body), signal: ctrl.signal });
    } catch (err) {
      const cause = err?.cause?.code || err?.name || err?.message;
      if (cause === 'ECONNREFUSED') {
        throw new ToolError('MTA_UNREACHABLE', `Cannot connect to the MTA HTTP server at ${config.mtaHost}:${config.mtaPort}.`, {
          retryable: true, cause, suggestion: 'Start the MTA server (check MTA_HOST / MTA_HTTP_PORT and <httpserver>/<httpport> in mtaserver.conf).',
        });
      }
      if (err?.name === 'AbortError') {
        throw new ToolError('BRIDGE_TIMEOUT', `The bridge did not answer ${category} within ${timeoutMs} ms.`, { retryable: true, suggestion: 'The server may be busy or frozen; check get_health.' });
      }
      throw new ToolError('MTA_HTTP_ERROR', `HTTP request failed: ${cause}`, { retryable: true });
    } finally {
      clearTimeout(timer);
    }
    const text = await res.text();
    if (res.status === 401) {
      throw new ToolError('HTTP_AUTH_REQUIRED', 'MTA refused the request (401): the guest HTTP account has no access.', {
        retryable: false, suggestion: 'Allow general.http for the Default ACL (see docs/installation.md) or set MTA_HTTP_USER / MTA_HTTP_PASS.',
      });
    }
    if (res.status === 404) {
      throw new ToolError('BRIDGE_NOT_RUNNING', `The '${config.resource}' resource is not running (HTTP 404 for ${category}).`, {
        retryable: true, suggestion: `In the MTA server console: refresh, then start ${config.resource}.`,
      });
    }
    if (!res.ok) {
      throw new ToolError('MTA_HTTP_ERROR', `MTA answered HTTP ${res.status}: ${text.slice(0, 200)}`, {
        retryable: res.status >= 500 || res.status === 429,
        suggestion: res.status === 429 || /flood|dos/i.test(text) ? 'HTTP DOS protection: add 127.0.0.1 to <http_dos_exclude> in mtaserver.conf.' : undefined,
      });
    }
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      throw new ToolError('BRIDGE_BAD_RESPONSE', `Bridge returned non-JSON: ${text.slice(0, 200)}`, { retryable: false });
    }
    return Array.isArray(data) ? data[0] : data;
  }

  #trackInstance(env) {
    const id = env?.instanceId;
    if (!id) return;
    if (this.instanceId && id !== this.instanceId) {
      this.restarts += 1;
      this.previousInstanceId = this.instanceId;
      this.pendingNotice = {
        code: 'BRIDGE_RESTARTED',
        message: 'The claude-mcp bridge restarted since the last call: every workspace, entity id and element ref from before is gone.',
        previousInstanceId: this.instanceId, instanceId: id,
      };
      for (const [job, w] of this.waiters) {
        w.reject(new ToolError('BRIDGE_RESTARTED', `Job ${job} was lost because the bridge restarted.`, { retryable: true }));
        clearTimeout(w.timer);
      }
      this.waiters.clear();
    }
    this.instanceId = id;
  }

  consumeNotice() {
    const n = this.pendingNotice;
    this.pendingNotice = null;
    return n;
  }

  #settle(jobId, envelope) {
    const w = this.waiters.get(jobId);
    if (!w || !envelope || envelope.pending) return;
    this.waiters.delete(jobId);
    clearTimeout(w.timer);
    if (envelope.ok) w.resolve(envelope.result);
    else w.reject(new ToolError(envelope.error?.code || 'BRIDGE_ERROR', envelope.error?.message || 'Bridge error', envelope.error || {}));
  }

  #ensurePolling() {
    if (this.pollTimer) return;
    this.pollTimer = setInterval(async () => {
      if (this.waiters.size === 0) {
        clearInterval(this.pollTimer);
        this.pollTimer = null;
        return;
      }
      const ids = [...this.waiters.keys()];
      try {
        const env = await this.#post('jobs', ['poll', { ids }], 10000);
        this.#trackInstance(env);
        if (env?.ok && env.result) {
          for (const [id, e] of Object.entries(env.result)) {
            if (e && !e.pending) this.#settle(id, e);
          }
        }
      } catch {
        /* keep waiting; timeouts reject */
      }
    }, config.pollIntervalMs);
  }

  #waitJob(jobId, timeoutMs) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters.delete(jobId);
        reject(new ToolError('JOB_TIMEOUT', `Bridge job ${jobId} did not finish within ${timeoutMs} ms.`, { retryable: true }));
      }, timeoutMs);
      this.waiters.set(jobId, { resolve, reject, timer });
      this.#ensurePolling();
    });
  }

  /** Calls category/action; resolves with the result, throws ToolError. */
  async call(category, action, params = {}, { timeoutMs = config.requestTimeoutMs } = {}) {
    const started = Date.now();
    this.requests += 1;
    try {
      const env = await this.#post(category, [action, clean(params), { callback: this.callbackUrl }], Math.min(timeoutMs, 20000));
      this.#trackInstance(env);
      let result;
      if (!env) throw new ToolError('BRIDGE_BAD_RESPONSE', 'Empty response from the bridge.');
      if (!env.ok) {
        throw new ToolError(env.error?.code || 'BRIDGE_ERROR', env.error?.message || 'Bridge error', env.error || {});
      }
      if (env.pending) result = await this.#waitJob(env.job, timeoutMs);
      else result = env.result;
      if (result && Array.isArray(result.imageChunks)) {
        // MTA caps JSON strings at 65535 chars; long data arrives in chunks
        result.image = result.imageChunks.join('');
        delete result.imageChunks;
      }
      this.lastSuccessAt = new Date().toISOString();
      this.latencies.push(Date.now() - started);
      if (this.latencies.length > 50) this.latencies.shift();
      return result;
    } catch (err) {
      this.failures += 1;
      this.lastError = { at: new Date().toISOString(), category, action, code: err.code, message: err.message };
      throw err;
    }
  }

  stats() {
    const l = this.latencies;
    return {
      url: bridgeUrl('<category>'),
      instanceId: this.instanceId,
      restartsDetected: this.restarts,
      lastSuccessAt: this.lastSuccessAt,
      lastError: this.lastError,
      requests: this.requests,
      failures: this.failures,
      pendingJobs: this.waiters.size,
      avgLatencyMs: l.length ? Math.round(l.reduce((a, b) => a + b, 0) / l.length) : null,
      callback: this.callbackUrl || this.callbackError || 'disabled',
    };
  }
}

// drop undefined values (MTA's JSON parser would turn them into null)
function clean(v) {
  if (Array.isArray(v)) return v.map(clean);
  if (v && typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) if (x !== undefined) out[k] = clean(x);
    return out;
  }
  return v;
}
