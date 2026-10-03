// Configuration from environment variables (all optional).
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const env = process.env;

export const config = {
  // MTA HTTP server (mtaserver.conf <httpport>) and the bridge resource name
  mtaHost: env.MTA_HOST || '127.0.0.1',
  mtaPort: Number(env.MTA_HTTP_PORT || 22005),
  resource: env.MTA_RESOURCE || 'claude-mcp',
  // optional MTA account for HTTP basic auth (only if your ACL requires it)
  httpUser: env.MTA_HTTP_USER || '',
  httpPass: env.MTA_HTTP_PASS || '',
  // local listener for job results pushed by the bridge (0 = disabled, poll only)
  callbackPort: Number(env.MCP_CALLBACK_PORT ?? 22095),
  requestTimeoutMs: Number(env.MCP_REQUEST_TIMEOUT || 60000),
  pollIntervalMs: Number(env.MCP_POLL_INTERVAL || 400),
  // road network (v_radar vehicle nodes)
  vehicleNodesPath: env.VEHICLE_NODES || path.resolve(here, '../../assets/vehiclenodes.lua'),
  // where screenshots are also written (empty = not saved)
  screenshotDir: env.MCP_SCREENSHOT_DIR ?? path.resolve(here, '../../screenshots'),
  // persistent data cache (surface maps, verified spots...)
  cacheDir: env.MCP_CACHE_DIR || path.resolve(here, '../../cache'),
  version: '1.0.0',
};

export function bridgeUrl(category) {
  // the "debug" category is exported as "dev" (a global named debug would shadow Lua's debug library)
  const fn = category === 'debug' ? 'dev' : category;
  return `http://${config.mtaHost}:${config.mtaPort}/${config.resource}/call/${fn}`;
}
