# frozen_string_literal: true

require "json"
require "mcp"

class UpdateSuggestion < MCP::Tool
  tool_name "update_suggestion"
  description "Update an existing suggested edit with new content"

  input_schema(
    properties: {
      suggestion_id: {
        type: "integer",
        description: "The ID of the suggested edit to update",
      },
      raw: {
        type: "string",
        description: "The updated suggested content for the post",
      },
      reason: {
        type: "string",
        description: "An optional updated reason for the suggested edit",
      },
    },
    required: %w[suggestion_id raw],
  )

  class << self
    def call(server_context:, suggestion_id:, raw:, reason: nil, **)
      body = { raw: raw }
      body[:reason] = reason if reason
      result = server_context.put("/suggested-edits/suggestions/#{suggestion_id}", body)
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(result) }])
    rescue DiscourseClient::ApiError => e
      MCP::Tool::Response.new(
        [{ type: "text", text: "API error (#{e.status}): #{e.body}" }],
        error: true,
      )
    end
  end
end
