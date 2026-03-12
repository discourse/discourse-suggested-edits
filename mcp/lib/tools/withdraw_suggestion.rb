# frozen_string_literal: true

require "json"
require "mcp"

class WithdrawSuggestion < MCP::Tool
  tool_name "withdraw_suggestion"
  description "Withdraw (delete) a pending suggested edit"

  input_schema(
    properties: {
      suggestion_id: {
        type: "integer",
        description: "The ID of the suggested edit to withdraw",
      },
    },
    required: %w[suggestion_id],
  )

  class << self
    def call(server_context:, suggestion_id:, **)
      server_context.delete("/suggested-edits/suggestions/#{suggestion_id}")
      MCP::Tool::Response.new(
        [{ type: "text", text: "Suggestion #{suggestion_id} has been withdrawn." }],
      )
    rescue DiscourseClient::ApiError => e
      MCP::Tool::Response.new(
        [{ type: "text", text: "API error (#{e.status}): #{e.body}" }],
        error: true,
      )
    end
  end
end
