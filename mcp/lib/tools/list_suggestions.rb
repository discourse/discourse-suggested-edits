# frozen_string_literal: true

require "json"
require "mcp"

class ListSuggestions < MCP::Tool
  tool_name "list_suggestions"
  description "List all pending suggested edits for a specific post"

  input_schema(
    properties: {
      post_id: {
        type: "integer",
        description: "The ID of the post to list suggested edits for",
      },
    },
    required: %w[post_id],
  )

  class << self
    def call(server_context:, post_id:, **)
      result = server_context.get("/suggested-edits/suggestions", post_id: post_id)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(result) }])
    rescue DiscourseClient::ApiError => e
      MCP::Tool::Response.new(
        [{ type: "text", text: "API error (#{e.status}): #{e.body}" }],
        error: true,
      )
    end
  end
end
