#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "mcp"

require_relative "lib/discourse_client"
require_relative "lib/tools/create_suggestion"
require_relative "lib/tools/get_suggestion"
require_relative "lib/tools/list_suggestions"
require_relative "lib/tools/update_suggestion"
require_relative "lib/tools/withdraw_suggestion"

options = {}

OptionParser
  .new do |opts|
    opts.banner = "Usage: ruby server.rb [options]"

    opts.on("--url URL", "Discourse base URL") { |v| options[:url] = v }
    opts.on("--api-key KEY", "Discourse API key") { |v| options[:api_key] = v }
    opts.on("--api-username USERNAME", "Discourse API username") { |v| options[:api_username] = v }
  end
  .parse!

url = options[:url] || ENV["DISCOURSE_URL"]
api_key = options[:api_key] || ENV["DISCOURSE_API_KEY"]
api_username = options[:api_username] || ENV["DISCOURSE_API_USERNAME"]

missing = []
missing << "URL (--url or DISCOURSE_URL)" unless url
missing << "API key (--api-key or DISCOURSE_API_KEY)" unless api_key

unless missing.empty?
  $stderr.puts "Error: Missing required configuration:"
  missing.each { |m| $stderr.puts "  - #{m}" }
  exit 1
end

client = DiscourseClient.new(url, api_key, api_username)

server =
  MCP::Server.new(
    name: "discourse-suggested-edits",
    version: "1.0.0",
    tools: [CreateSuggestion, GetSuggestion, ListSuggestions, UpdateSuggestion, WithdrawSuggestion],
    server_context: client,
  )

transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
