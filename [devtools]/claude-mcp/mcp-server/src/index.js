#!/usr/bin/env node
// MTA World MCP server (stdio transport).
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createContext, createServer } from './server.js';

const ctx = await createContext();
const server = createServer(ctx);
await server.connect(new StdioServerTransport());
process.stderr.write(`[mta-world-mcp] ready; bridge ${ctx.bridge.stats().url}, road nodes ${ctx.roads.stats().nodes}\n`);
