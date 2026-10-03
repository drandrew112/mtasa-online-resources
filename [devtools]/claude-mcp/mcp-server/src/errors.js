// Structured errors shared by the bridge client and the tools.

export class ToolError extends Error {
  constructor(code, message, extra = {}) {
    super(message);
    this.code = code;
    this.extra = extra;
  }
  toJSON() {
    return { code: this.code, message: this.message, ...this.extra };
  }
}

export function asErrorObject(err) {
  if (err instanceof ToolError) return err.toJSON();
  if (err && typeof err === 'object' && err.code && err.message) return err;
  return {
    code: 'INTERNAL_ERROR',
    message: String(err?.message || err),
    retryable: false,
    suggestion: 'Unexpected MCP server error; check get_health and the MCP server stderr.',
  };
}

export const fail = (code, message, extra) => {
  throw new ToolError(code, message, extra);
};
