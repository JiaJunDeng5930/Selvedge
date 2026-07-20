#!/bin/sh

mode="$1"

if [ -n "${MCP_CLOSE_MARKER:-}" ]; then
  trap 'printf closed > "$MCP_CLOSE_MARKER"' EXIT
fi

if [ -n "${MCP_DESCENDANT_PID_MARKER:-}" ]; then
  (
    while :; do
      sleep 60
    done
  ) &
  printf '%s' "$!" > "$MCP_DESCENDANT_PID_MARKER"
fi

request_id() {
  printf '%s\n' "$1" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p'
}

large_description() {
  dd if=/dev/zero bs=100000 count="$1" 2>/dev/null | tr '\000' x
}

while IFS= read -r request; do
  case "$request" in
    *'"method":"initialize"'*)
      id="$(request_id "$request")"
      printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"selvedge-test\",\"version\":\"1\"}}}"
      ;;
    *'"method":"tools/list"'*)
      id="$(request_id "$request")"
      if [ "$mode" = "required" ]; then
        printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"task.only\",\"description\":\"requires MCP task mode\",\"inputSchema\":{\"type\":\"object\"},\"execution\":{\"taskSupport\":\"required\"}}]}}"
      elif [ "$mode" = "collision" ]; then
        printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"same.name\",\"inputSchema\":{\"type\":\"object\"}},{\"name\":\"same_name\",\"inputSchema\":{\"type\":\"object\"}}]}}"
      elif [ "$mode" = "catalog-overflow" ]; then
        if printf '%s' "$request" | grep -q '"cursor":"page-2"'; then
          printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"large-two\",\"description\":\""
          large_description 22
          printf '%s\n' "\",\"inputSchema\":{\"type\":\"object\"}}]}}"
        else
          printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"large-one\",\"description\":\""
          large_description 22
          printf '%s\n' "\",\"inputSchema\":{\"type\":\"object\"}}],\"nextCursor\":\"page-2\"}}"
        fi
      elif printf '%s' "$request" | grep -q '"cursor":"page-2"'; then
        printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"fail\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}}]}}"
      else
        printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"tools\":[{\"name\":\"echo.value\",\"description\":\"echoes structured JSON\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"value\":{}},\"required\":[\"value\"]}}],\"nextCursor\":\"page-2\"}}"
      fi
      ;;
    *'"method":"tools/call"'*)
      id="$(request_id "$request")"
      if [ -n "${MCP_REQUEST_MARKER:-}" ]; then
        printf '%s' "$request" > "$MCP_REQUEST_MARKER"
      fi
      if [ "$mode" = "slow" ]; then
        continue
      fi
      if [ "$mode" = "disconnect" ]; then
        exit 0
      fi
      if [ "$mode" = "oversize-call" ]; then
        printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\""
        large_description 42
        printf '%s\n' "\"}]}}"
        continue
      fi
      printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"remote failure\"}],\"structuredContent\":{\"nested\":[1,true,null]},\"isError\":true,\"_meta\":{\"source\":\"fixture\"}}}"
      ;;
    *'"method":"notifications/cancelled"'*)
      if [ -n "${MCP_CANCEL_MARKER:-}" ]; then
        printf '%s' "$request" > "$MCP_CANCEL_MARKER.tmp"
        mv "$MCP_CANCEL_MARKER.tmp" "$MCP_CANCEL_MARKER"
      fi
      ;;
  esac
done
