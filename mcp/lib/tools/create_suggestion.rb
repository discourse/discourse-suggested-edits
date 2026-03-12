# frozen_string_literal: true

require "json"
require "mcp"

class CreateSuggestion < MCP::Tool
  tool_name "create_suggestion"
  description "Create a suggested edit for a Discourse post's content"

  input_schema(
    properties: {
      post_id: {
        type: "integer",
        description: "The ID of the post to suggest an edit for",
      },
      raw: {
        type: "string",
        description: "The suggested new content for the post",
      },
      reason: {
        type: "string",
        description: "An optional reason explaining the suggested edit",
      },
    },
    required: %w[post_id raw],
  )

  class << self
    def call(server_context:, post_id:, raw:, reason: nil, **)
      body = { post_id: post_id, raw: raw }
      body[:reason] = reason if reason
      result = server_context.post("/suggested-edits/suggestions", body)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(result) }])
    rescue DiscourseClient::ApiError => e
      MCP::Tool::Response.new(
        [{ type: "text", text: "API error (#{e.status}): #{e.body}" }],
        error: true,
      )
    end
  end
end
