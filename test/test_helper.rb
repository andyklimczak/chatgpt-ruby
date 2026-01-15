# frozen_string_literal: true

require 'simplecov'
require 'simplecov_json_formatter'

SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  track_files '{lib}/**/*.rb'

  enable_coverage :branch

  formatter SimpleCov::Formatter::MultiFormatter.new([
                                                       SimpleCov::Formatter::HTMLFormatter,
                                                       SimpleCov::Formatter::JSONFormatter
                                                     ])
end

require 'minitest/autorun'
require 'webmock/minitest'
require 'json'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'chatgpt'

module TestHelpers
  def mock_response_body(choices:, id:, obj:, model:, usage: nil)
    usage ||= { 'prompt_tokens' => 10, 'completion_tokens' => 20, 'total_tokens' => 30 }
    {
      'choices' => choices,
      'created' => Time.now.to_i,
      'id' => id,
      'model' => model,
      'object' => obj,
      'usage' => usage
    }
  end

  def stub_completions_request(params = {})
    n = params[:n] || 1
    choices = Array.new(n) do |i|
      { 'finish_reason' => 'stop', 'index' => i, 'text' => "Sample response #{i + 1}" }
    end

    response_body = mock_response_body(
      id: 'cmpl-123',
      obj: 'text_completion',
      model: params[:engine] || 'gpt-4o-mini',
      choices: choices
    )

    stub_request(:post, %r{https://api\.openai\.com/v1/engines/.*/completions})
      .with(headers: { 'Authorization' => "Bearer #{@api_key}" })
      .to_return(
        status: 200,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_error_request(status_code, error_message)
    stub_request(:post, %r{https://api\.openai\.com/v1/engines/.*/completions})
      .with(headers: { 'Authorization' => "Bearer #{@api_key}" })
      .to_return(
        status: status_code,
        body: {
          error: {
            message: error_message,
            type: 'invalid_request_error',
            code: status_code
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_responses_request(params = {})
    response_body = {
      'id' => 'resp-123',
      'object' => 'response',
      'model' => params[:model] || 'gpt-5-mini',
      'output' => [
        {
          'id' => 'rs-123',
          'type' => 'reasoning',
          'summary' => []
        },
        {
          'id' => 'msg-123',
          'type' => 'message',
          'role' => 'assistant',
          'content' => [
            { 'type' => 'output_text', 'text' => 'Hello! How can I help you today?' }
          ]
        }
      ]
    }

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with(headers: { 'Authorization' => "Bearer #{@api_key}" })
      .to_return(
        status: 200,
        body: response_body.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_responses_stream_request
    chunks = [
      { 'type' => 'response.output_text.delta', 'delta' => 'Hello' },
      { 'type' => 'response.output_text.delta', 'delta' => '!' },
      { 'type' => 'response.output_text.done', 'text' => 'Hello!' }
    ]

    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with(headers: { 'Authorization' => "Bearer #{@api_key}" })
      .to_return(
        status: 200,
        body: "#{chunks.map { |chunk| "data: #{chunk.to_json}\n\n" }.join}data: [DONE]\n\n",
        headers: { 'Content-Type' => 'text/event-stream' }
      )
  end

  def stub_responses_error_request(status_code, error_message)
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .with(headers: { 'Authorization' => "Bearer #{@api_key}" })
      .to_return(
        status: status_code,
        body: {
          error: {
            message: error_message,
            type: 'invalid_request_error',
            code: status_code
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end
