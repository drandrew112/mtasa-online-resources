import subprocess, json, sys, os
MCP = r"C:\Dev\MTASA\server\mods\deathmatch\resources\[devtools]\claude-mcp\mcp-server"
RUNNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_tool.mjs")

def call(tool, args, timeout=300):
    argfile = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_args.json")
    with open(argfile, "w", encoding="utf-8") as f:
        json.dump({"tool": tool, "args": args}, f)
    p = subprocess.run(["node", RUNNER, argfile], cwd=MCP, capture_output=True, text=True, timeout=timeout, encoding="utf-8")
    line = p.stdout.strip().split("\n")[0] if p.stdout.strip() else ""
    try:
        return json.loads(line)
    except Exception:
        raise RuntimeError("bad output: " + p.stdout[:2000] + "\nERR " + p.stderr[:2000])

def lua(code, timeout=120):
    r = call("execute_lua", {"code": code, "side": "client", "timeout": timeout * 1000}, timeout + 30)
    return r

if __name__ == "__main__":
    print(json.dumps(call(sys.argv[1], json.loads(sys.argv[2])))[:5000])
