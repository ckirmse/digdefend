"""Drive StudioMCP.exe over stdio JSON-RPC.

Usage: python studio_mcp.py <tool> [<json-args-file>]
Prints the tool result's text content. One process per call.
"""
import json
import subprocess
import sys
import time

EXE = r"C:\Users\dinob\AppData\Local\Roblox\Versions\version-7062aec9dbe74b14\StudioMCP.exe"


def main():
    tool = sys.argv[1]
    args = {}
    if len(sys.argv) > 2:
        with open(sys.argv[2], encoding="utf-8") as handle:
            args = json.load(handle)
    proc = subprocess.Popen(
        [EXE],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        bufsize=1,
    )

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def recv(wanted_id):
        while True:
            line = proc.stdout.readline()
            if not line:
                raise SystemExit("StudioMCP closed")
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == wanted_id:
                return msg

    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "claude-fallback", "version": "1"},
    }})
    recv(1)
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    time.sleep(4)
    send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": tool, "arguments": args}})
    result = recv(2)
    proc.stdin.close()
    if "error" in result:
        print("ERROR:", json.dumps(result["error"]))
        return
    content = result.get("result", {}).get("content", [])
    for item in content:
        if item.get("type") == "text":
            print(item["text"])
        else:
            print("[non-text item:", item.get("type"), "]")
    if result.get("result", {}).get("isError"):
        print("[isError]")


if __name__ == "__main__":
    main()
