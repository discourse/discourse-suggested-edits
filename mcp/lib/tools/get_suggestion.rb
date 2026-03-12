# frozen_string_literal: true

require "json"
require "mcp"

class GetSuggestion < MCP::Tool
  tool_name "get_suggestion"
  description "Get details of a specific suggested edit"

  input_schema(
    properties: {
      suggestion_id: {
        type: "integer",
        description: "The ID of the suggested edit to retrieve",
      },
    },
    required: %w[suggestion_id],
  )

  class << self
    def call(server_context:, suggestion_id:, **)
      result = server_context.get("/suggested-edits/suggestions/#{suggestion_id}")
      MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(result) }])
    rescue DiscourseClient::ApiError => e
      MCP::Tool::Response.new(
        [{ type: "text", text: "API error (#{e.status}): #{e.body}" }],
        error: true,
      )
    end
  end
end
