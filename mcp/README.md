# Discourse Suggested Edits MCP Server

A standalone [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server that enables AI agents to suggest edits to Discourse posts via the `discourse-suggested-edits` plugin API.

This server covers the **suggester** workflow only (creating, viewing, updating, and withdrawing suggestions). Reviewer actions (apply/dismiss) and topic reading are handled separately.

## Prerequisites

- Ruby 3.0+
- A Discourse instance with the `discourse-suggested-edits` plugin enabled
- A Discourse API key scoped to `discourse_suggested_edits:suggest_edits`

## Installation

```bash
cd plugins/discourse-suggested-edits/mcp
bundle install
```

## Creating an API Key

1. Go to your Discourse admin panel → API → Keys
2. Create a new API key
3. Set the scope to **discourse_suggested_edits:suggest_edits**
4. Assign it to the user that will author suggestions (e.g., `system`)

This scope grants access to: list, show, create, update, and destroy suggestions.

## Running

### Via environment variables

```bash
DISCOURSE_URL=http://localhost:3000 \
DISCOURSE_API_KEY=your_api_key \
DISCOURSE_API_USERNAME=system \
ruby server.rb
```

### Via CLI flags

```bash
ruby server.rb \
  --url http://localhost:3000 \
  --api-key your_api_key \
  --api-username system
```

CLI flags take precedence over environment variables.

## MCP Harness Configuration

Example configuration for mounting this server in an MCP-compatible harness:

```json
{
  "mcpServers": {
    "discourse-suggested-edits": {
      "command": "ruby",
      "args": ["server.rb"],
      "cwd": "plugins/discourse-suggested-edits/mcp",
      "env": {
        "DISCOURSE_URL": "http://localhost:3000",
        "DISCOURSE_API_KEY": "your_api_key",
        "DISCOURSE_API_USERNAME": "system"
      }
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `create_suggestion` | Create a suggested edit for a post's content |
| `get_suggestion` | Get details of a specific suggested edit |
| `list_suggestions` | List all pending suggested edits for a post |
| `update_suggestion` | Update an existing suggested edit with new content |
| `withdraw_suggestion` | Withdraw (delete) a pending suggested edit |

### Tool Parameters

#### `create_suggestion`
- `post_id` (integer, required) — The ID of the post to suggest an edit for
- `raw` (string, required) — The suggested new content for the post
- `reason` (string, optional) — A reason explaining the suggested edit

#### `get_suggestion`
- `suggestion_id` (integer, required) — The ID of the suggested edit to retrieve

#### `list_suggestions`
- `post_id` (integer, required) — The ID of the post to list suggestions for

#### `update_suggestion`
- `suggestion_id` (integer, required) — The ID of the suggested edit to update
- `raw` (string, required) — The updated suggested content
- `reason` (string, optional) — An updated reason for the edit

#### `withdraw_suggestion`
- `suggestion_id` (integer, required) — The ID of the suggested edit to withdraw

## Example Workflow

```
1. create_suggestion(post_id: 42, raw: "Updated content...", reason: "Fix typo")
   → Returns the created suggestion with ID, status, and change details

2. list_suggestions(post_id: 42)
   → Returns all pending suggestions for the post

3. get_suggestion(suggestion_id: 1)
   → Returns full details including diff and context

4. update_suggestion(suggestion_id: 1, raw: "Better content...", reason: "Improved fix")
   → Returns the updated suggestion

5. withdraw_suggestion(suggestion_id: 1)
   → Confirms the suggestion has been withdrawn
```
