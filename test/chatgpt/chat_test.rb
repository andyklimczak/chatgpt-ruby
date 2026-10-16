# frozen_string_literal: true

# test/chatgpt/chat_test.rb
require 'test_helper'

class TestChatGPTChatIntegration < Minitest::Test
  include TestHelpers

  def setup
    super
    ChatGPT.reset_configuration!
    @api_key = 'test-key'
    @client = ChatGPT::Client.new(@api_key)
  end

  def teardown
    ChatGPT.reset_configuration!
    super
  end

  def test_default_reasoning_for_gpt_5_and_forward_compatible_gpt_6_model_ids
    %w[gpt-5 gpt-5-mini gpt-5.4-mini gpt-5.5 gpt-6 gpt-6.1 gpt-6-mini gpt-6.1-2099-01-01].each do |model|
      WebMock.reset!
      stub_responses_request(model: model)

      ChatGPT::Client.new(@api_key, model).chat([{ role: 'user', content: 'Hello!' }])

      assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
        body = JSON.parse(request.body)
        body['model'] == model && body['reasoning'] == { 'effort' => 'low' }
      end
    end
  end

  def test_other_models_do_not_receive_automatic_reasoning
    %w[gpt-4o-mini gpt-4.1 gpt-50 custom-model].each do |model|
      WebMock.reset!
      stub_responses_request(model: model)

      @client.chat([{ role: 'user', content: 'Hello!' }], model: model)

      assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
        body = JSON.parse(request.body)
        body['model'] == model && !body.key?('reasoning')
      end
    end
  end

  def test_configured_reasoning_effort
    ChatGPT.configuration.reasoning_effort = 'medium'
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-5.5')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      JSON.parse(request.body)['reasoning'] == { 'effort' => 'medium' }
    end
  end

  def test_request_reasoning_effort_overrides_configuration
    ChatGPT.configuration.reasoning_effort = 'medium'
    ChatGPT.configuration.default_parameters[:reasoning] = { effort: 'low' }
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-6.1', reasoning_effort: 'high')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      body = JSON.parse(request.body)
      body['reasoning'] == { 'effort' => 'high' } && !body.key?('reasoning_effort')
    end
  end

  def test_raw_reasoning_overrides_effort_shorthand
    stub_responses_request

    @client.chat(
      [{ role: 'user', content: 'Hello!' }],
      model: 'gpt-5.5',
      reasoning_effort: 'high',
      reasoning: { effort: 'medium', summary: 'auto' }
    )

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      JSON.parse(request.body)['reasoning'] == { 'effort' => 'medium', 'summary' => 'auto' }
    end
  end

  def test_raw_reasoning_defaults_override_configured_effort
    ChatGPT.configuration.reasoning_effort = 'low'
    ChatGPT.configuration.default_parameters[:reasoning] = { effort: 'medium', summary: 'auto' }
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-5.5')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      JSON.parse(request.body)['reasoning'] == { 'effort' => 'medium', 'summary' => 'auto' }
    end
    assert_equal({ effort: 'medium', summary: 'auto' }, ChatGPT.configuration.default_parameters[:reasoning])
  end

  def test_explicit_reasoning_is_forwarded_for_other_models
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'o3', reasoning_effort: 'high')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      body = JSON.parse(request.body)
      body['model'] == 'o3' && body['reasoning'] == { 'effort' => 'high' }
    end
  end

  def test_nil_request_reasoning_omits_reasoning
    [{ reasoning: nil }, { reasoning_effort: nil }].each do |params|
      WebMock.reset!
      ChatGPT.configuration.default_parameters[:reasoning] = { effort: 'medium' }
      stub_responses_request

      @client.chat([{ role: 'user', content: 'Hello!' }], params.merge(model: 'gpt-5.5'))

      assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
        !JSON.parse(request.body).key?('reasoning')
      end
    end
  end

  def test_nil_configured_effort_uses_api_default
    ChatGPT.configuration.reasoning_effort = nil
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-5.5')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      !JSON.parse(request.body).key?('reasoning')
    end
  end

  def test_nil_raw_reasoning_default_uses_api_default
    ChatGPT.configuration.default_parameters[:reasoning] = nil
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-6')

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      !JSON.parse(request.body).key?('reasoning')
    end
  end

  def test_effort_values_are_forwarded_without_a_model_specific_allowlist
    %w[none minimal low medium high xhigh].each do |effort|
      WebMock.reset!
      stub_responses_request

      @client.chat([{ role: 'user', content: 'Hello!' }], model: 'gpt-5.5', reasoning_effort: effort)

      assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
        JSON.parse(request.body)['reasoning'] == { 'effort' => effort }
      end
    end
  end

  def test_responses_supports_reasoning_effort_and_configured_output_budget
    ChatGPT.configuration.default_parameters = { max_output_tokens: 8_000 }
    stub_responses_request
    serialized_request = nil

    @client.responses(
      [{ role: 'user', content: 'Hello!' }],
      model: 'gpt-6.1',
      reasoning_effort: 'medium',
      before_request: ->(body) { serialized_request = body }
    )

    body = JSON.parse(serialized_request)
    assert_equal 'gpt-6.1', body['model']
    assert_equal({ 'effort' => 'medium' }, body['reasoning'])
    assert_equal 8_000, body['max_output_tokens']
  end

  def test_request_output_budget_overrides_configured_budget
    ChatGPT.configuration.default_parameters = { max_output_tokens: 8_000 }
    stub_responses_request

    @client.chat([{ role: 'user', content: 'Hello!' }], max_output_tokens: 12_000)

    assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
      JSON.parse(request.body)['max_output_tokens'] == 12_000
    end
  end

  def test_streaming_supports_reasoning_effort_and_model_overrides
    %w[gpt-5.5 gpt-6 gpt-6.1].each do |model|
      WebMock.reset!
      stub_responses_stream_request
      chunks = []

      @client.chat_stream([{ role: 'user', content: 'Hello!' }], model: model, reasoning_effort: 'high') do |chunk|
        chunks << chunk
      end

      assert chunks.any?
      assert_requested(:post, 'https://api.openai.com/v1/responses') do |request|
        body = JSON.parse(request.body)
        body['model'] == model && body['stream'] && body['reasoning'] == { 'effort' => 'high' }
      end
    end
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
