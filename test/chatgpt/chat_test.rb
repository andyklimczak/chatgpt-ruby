# frozen_string_literal: true

# test/chatgpt/chat_test.rb
require 'test_helper'

class TestChatGPTChatIntegration < Minitest::Test
  include TestHelpers

  def setup
    @api_key = 'test-key'
    @client = ChatGPT::Client.new(@api_key)
  end

  def test_basic_chat
    stub_responses_request
    messages = [{ role: 'user', content: 'Hello!' }]
    response = @client.chat(messages)
    message = response['output'].find { |item| item['type'] == 'message' }

    assert message
    assert message.dig('content', 0, 'text')
    assert_equal 'assistant', message['role']
  end

  def test_chat_with_default_model_override
    client = ChatGPT::Client.new(@api_key, 'gpt-4o-mini')
    stub_responses_request(model: 'gpt-4o-mini')
    messages = [{ role: 'user', content: 'Hello!' }]
    response = client.chat(messages)
    message = response['output'].find { |item| item['type'] == 'message' }

    assert message&.dig('content', 0, 'text')
  end

  def test_chat_uses_responses_api
    client = ChatGPT::Client.new(@api_key, 'gpt-4o-mini')
    stub_responses_request(model: 'gpt-4o-mini')
    messages = [{ role: 'user', content: 'Hello!' }]
    response = client.chat(messages)

    message = response['output'].find { |item| item['type'] == 'message' }

    assert message
    assert_equal 'assistant', message['role']
    assert message.dig('content', 0, 'text')
    assert_requested(:post, 'https://api.openai.com/v1/responses')
  end

  def test_chat_with_system_message
    stub_responses_request
    messages = [
      { role: 'system', content: 'You are a helpful assistant.' },
      { role: 'user', content: 'Hello!' }
    ]

    response = @client.chat(messages)
    message = response['output'].find { |item| item['type'] == 'message' }
    assert message&.dig('content', 0, 'text')
  end

  def test_chat_with_custom_parameters
    stub_responses_request(temperature: 0.7)
    messages = [{ role: 'user', content: 'Hello!' }]
    response = @client.chat(messages, temperature: 0.7)
    message = response['output'].find { |item| item['type'] == 'message' }

    assert message&.dig('content', 0, 'text')
  end

  def test_chat_streaming
    stub_responses_stream_request
    messages = [{ role: 'user', content: 'Hello!' }]
    chunks = []

    @client.chat_stream(messages) do |chunk|
      chunks << chunk
    end

    assert chunks.length.positive?
    assert(chunks.all? { |c| c['type'] })
  end

  def test_chat_with_invalid_messages
    stub_responses_error_request(400, 'Invalid messages format')
    error = assert_raises(ChatGPT::InvalidRequestError) do
      @client.chat([])
    end
    assert_equal 400, error.status_code
    assert_equal 'Invalid messages format', error.message
  end

  def test_chat_with_rate_limit
    stub_responses_error_request(429, 'Rate limit exceeded')
    error = assert_raises(ChatGPT::RateLimitError) do
      @client.chat([{ role: 'user', content: 'Hello!' }])
    end
    assert_equal 429, error.status_code
  end

  def test_responses_preserve_safety_identifier_storage_schema_and_request_id
    schema = {
      type: 'object',
      properties: { value: { type: 'string' } },
      required: ['value'],
      additionalProperties: false
    }
    identifier = "v12.#{'a' * 43}"
    stub_responses_request(request_id: 'req_123')
    serialized_request = nil

    response = @client.responses(
      [{ role: 'user', content: 'Hello!' }],
      store: false,
      safety_identifier: identifier,
      reasoning: { effort: 'low', context: 'current_turn' },
      text: { format: { type: 'json_schema', name: 'result', strict: true, schema: schema } },
      before_request: ->(body) { serialized_request = body }
    )

    assert_equal 'req_123', response.request_id
    assert_equal 'response', response.body['object']
    assert_equal identifier, JSON.parse(serialized_request)['safety_identifier']
    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      body = JSON.parse(request.body)
      body['store'] == false &&
        body['safety_identifier'] == identifier &&
        body.dig('reasoning', 'context') == 'current_turn' &&
        body.dig('text', 'format', 'schema') == JSON.parse(schema.to_json)
    end
  end

  def test_responses_reject_invalid_safety_identifier
    error = assert_raises(ArgumentError) do
      @client.responses([{ role: 'user', content: 'Hello!' }], safety_identifier: 'athlete-123')
    end

    assert_match 'safety_identifier', error.message
  end

  def test_retries_retryable_responses_with_retry_after
    delays = []
    client = ChatGPT::Client.new(@api_key, nil, sleeper: ->(delay) { delays << delay }, jitter: -> { 0 })
    stub_request(:post, 'https://api.openai.com/v1/responses')
      .to_return(status: 429, body: { error: { message: 'Rate limit exceeded' } }.to_json, headers: { 'Retry-After' => '1' })
      .then
      .to_return(status: 200, body: { id: 'resp-123', object: 'response', output: [] }.to_json, headers: { 'X-Request-Id' => 'req_123' })

    response = client.responses([{ role: 'user', content: 'Hello!' }])

    assert_equal 'req_123', response.request_id
    assert_equal [1.0], delays
    assert_requested :post, 'https://api.openai.com/v1/responses', times: 2
  end

  def test_retries_retryable_statuses
    [408, 409, 500].each do |status|
      WebMock.reset!
      delays = []
      client = ChatGPT::Client.new(@api_key, nil, sleeper: ->(delay) { delays << delay }, jitter: -> { 0 })
      stub_request(:post, 'https://api.openai.com/v1/responses')
        .to_return(status: status, body: { error: { message: 'Retry me' } }.to_json)
        .then
        .to_return(status: 200, body: { id: 'resp-123', object: 'response', output: [] }.to_json)

      client.responses([{ role: 'user', content: 'Hello!' }])

      assert_equal [0.5], delays
      assert_requested :post, 'https://api.openai.com/v1/responses', times: 2
    end
  end

  def test_stops_after_the_configured_retry_budget
    original_retries = ChatGPT.configuration.max_retries
    ChatGPT.configuration.max_retries = 1
    stub_responses_error_request(500, 'Temporary error')

    error = assert_raises(ChatGPT::APIError) do
      @client.responses([{ role: 'user', content: 'Hello!' }])
    end

    assert_equal 500, error.status_code
    assert_requested :post, 'https://api.openai.com/v1/responses', times: 2
  ensure
    ChatGPT.configuration.max_retries = original_retries
  end

  def test_retries_timeouts_and_returns_a_typed_timeout_error
    original_retries = ChatGPT.configuration.max_retries
    ChatGPT.configuration.max_retries = 1
    delays = []
    client = ChatGPT::Client.new(@api_key, nil, sleeper: ->(delay) { delays << delay }, jitter: -> { 0 })
    stub_request(:post, 'https://api.openai.com/v1/responses').to_timeout

    assert_raises(ChatGPT::TimeoutError) do
      client.responses([{ role: 'user', content: 'Hello!' }])
    end

    assert_equal [0.5], delays
    assert_requested :post, 'https://api.openai.com/v1/responses', times: 2
  ensure
    ChatGPT.configuration.max_retries = original_retries
  end

  def test_uses_separate_connect_and_read_timeouts
    original_open_timeout = ChatGPT.configuration.open_timeout
    original_request_timeout = ChatGPT.configuration.request_timeout
    ChatGPT.configuration.open_timeout = 3
    ChatGPT.configuration.request_timeout = 7
    captured_options = nil
    response = Struct.new(:body, :code, :headers).new({ id: 'resp-123', object: 'response', output: [] }.to_json, 200, {})
    transport = Object.new
    transport.define_singleton_method(:execute) do |options|
      captured_options = options
      response
    end

    ChatGPT::Client.new(@api_key, nil, transport: transport).responses([{ role: 'user', content: 'Hello!' }])

    assert_equal 3, captured_options[:open_timeout]
    assert_equal 7, captured_options[:timeout]
  ensure
    ChatGPT.configuration.open_timeout = original_open_timeout
    ChatGPT.configuration.request_timeout = original_request_timeout
  end
end
