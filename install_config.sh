#!/bin/bash

# Create Claude config directory if it doesn't exist
mkdir -p ~/Library/Application\ Support/Claude/

# Copy the config file
cat > ~/Library/Application\ Support/Claude/claude_desktop_config.json << 'EOF'
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-supabase@latest",
        "--read-only",
        "--project-ref=wfxlihpxeeyjlllvoypa"
      ],
      "env": {
        "SUPABASE_ACCESS_TOKEN": "sbp_65e1269b9a89f576884fbec93d3db464c30282f8"
      }
    }
  }
}
EOF

echo "✅ Claude Desktop MCP config installed!"
echo "📍 Location: ~/Library/Application Support/Claude/claude_desktop_config.json"
echo "🔄 Restart Claude Desktop app to apply changes"