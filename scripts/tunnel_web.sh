#!/bin/bash
exec /workspace/tools/cloudflared tunnel --url http://127.0.0.1:8765 --no-autoupdate
