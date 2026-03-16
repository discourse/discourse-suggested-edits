# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class DiscourseClient
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(status, body)
      @status = status
      @body = body
      super("API request failed with status #{status}")
    end
  end

  def initialize(base_url, api_key, api_username)
    @base_url = base_url.chomp("/")
    @api_key = api_key
    @api_username = api_username
  end

  def get(path, params = {})
    uri = build_uri(path, params)
    request = Net::HTTP::Get.new(uri)
    set_headers(request)
    execute(uri, request)
  end

  def post(path, body = {})
    uri = build_uri(path)
    request = Net::HTTP::Post.new(uri)
    set_headers(request)
    request.body = JSON.generate(body)
    execute(uri, request)
  end

  def put(path, body = {})
    uri = build_uri(path)
    request = Net::HTTP::Put.new(uri)
    set_headers(request)
    request.body = JSON.generate(body)
    execute(uri, request)
  end

  def delete(path)
    uri = build_uri(path)
    request = Net::HTTP::Delete.new(uri)
    set_headers(request)
    execute(uri, request)
  end

  private

  def build_uri(path, params = {})
    uri = URI("#{@base_url}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    uri
  end

  def set_headers(request)
    request["Api-Key"] = @api_key
    request["Api-Username"] = @api_username if @api_username
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
  end

  def execute(uri, request)
    response =
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

    return nil if response.code == "204"

    raise ApiError.new(response.code.to_i, response.body) unless response.code.start_with?("2")

    JSON.parse(response.body)
  end
end
