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
end
