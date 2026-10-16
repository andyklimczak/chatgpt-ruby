# ChatGPT Ruby - GPT-5 and Configurable Thinking

[![CI](https://github.com/andyklimczak/chatgpt-ruby/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/andyklimczak/chatgpt-ruby/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

A lightweight Ruby client for OpenAI's Responses API, maintained in
[andyklimczak/chatgpt-ruby](https://github.com/andyklimczak/chatgpt-ruby).
Based on the original `chatgpt-ruby` project, with the changes from
[ujh/chatgpt-ruby](https://github.com/ujh/chatgpt-ruby) incorporated.

## Features

- GPT-5 family model IDs, including `gpt-5.5` and `gpt-5.4-mini`.
- Configurable thinking (reasoning effort), globally and per request.
- Forward-compatible handling of `gpt-6` and `gpt-6.1` model IDs. Their API availability and behavior are **not verified**; see [Supported Models](#supported-models).
- Chat, streaming, JSON output formats, and response metadata through the Responses API.
- Connection/read timeouts, configurable retries, and typed API errors.
- Tests with mocked API responses; no API key is needed to run the suite.

## Installation

Use this fork's `main` branch to get these features:

```ruby
gem 'chatgpt-ruby', github: 'andyklimczak/chatgpt-ruby', branch: 'main'
```

Then run `bundle install`. If already using the fork, run `bundle update chatgpt-ruby`.
The RubyGems release may not contain the changes documented here.
Requires Ruby 3.0 or later.

## Quick Start

```ruby
require 'chatgpt'

ChatGPT.configure do |config|
  config.api_key = ENV.fetch('OPENAI_API_KEY')
  config.default_engine = 'gpt-5.5'
  config.reasoning_effort = 'medium'
  config.default_parameters = { max_output_tokens: 8000 }
end

client = ChatGPT::Client.new
messages = [{ role: 'user', content: 'Write a natural A1 English listening sentence.' }]
response = client.chat(messages)

message = response['output']&.find { |item| item['type'] == 'message' }
puts message&.dig('content', 0, 'text')
```

## Thinking / Reasoning Effort

Set the default with `config.reasoning_effort`, and override it per request:

```ruby
ChatGPT.configure do |config|
  config.reasoning_effort = 'medium'
end

response = client.chat(messages, reasoning_effort: 'high')

# The native Responses API format is also supported.
response = client.chat(messages, reasoning: { effort: 'medium', summary: 'auto' })

# Model selection can also be overridden per request.
response = client.chat(messages, model: 'gpt-5.4-mini', reasoning_effort: 'low')
```

The `reasoning_effort` shorthand is serialized as `reasoning: { effort: ... }`.
It works with `chat`, `responses`, and `chat_stream`.
Explicit reasoning parameters are forwarded for any model ID; OpenAI validates
whether that model supports them.

GPT-5.5 accepts `none`, `low`, `medium`, `high`, and `xhigh`, according to its
[model documentation](https://developers.openai.com/api/docs/models/gpt-5.5).
Supported effort levels depend on the model. The gem does not enforce an effort
allowlist or assume that future models support the same levels.
Higher effort can increase latency and reasoning-token usage; it does not
guarantee better output.

### Defaults and Precedence

For GPT-5 and GPT-6 family model IDs, the gem defaults to `low` effort to preserve
this fork's existing GPT-5 behavior. Other model IDs receive no automatic
reasoning parameter. The GPT-6 family handling is a client-side compatibility
rule, not confirmation that those models or parameters are available.

Reasoning is selected in this order, highest priority first:

1. Per-request `reasoning`, including explicit `nil`.
2. Per-request `reasoning_effort`, including explicit `nil`.
3. `config.default_parameters[:reasoning]`, including explicit `nil`.
4. `config.reasoning_effort`, for GPT-5/GPT-6 family IDs only.

Each selection replaces the lower-priority reasoning settings; hashes are not merged.
You can configure the native reasoning object as a default:

```ruby
ChatGPT.configure do |config|
  config.default_parameters = {
    max_output_tokens: 8000,
    reasoning: { effort: 'medium', summary: 'auto' }
  }
end
```

To omit reasoning parameters and use OpenAI's model default:

```ruby
# Globally, when no raw reasoning default is configured:
ChatGPT.configure { |config| config.reasoning_effort = nil }

# For one request, overriding all gem defaults:
response = client.chat(messages, reasoning: nil)
# Equivalent shorthand:
response = client.chat(messages, reasoning_effort: nil)
```

Omitting reasoning is different from `reasoning_effort: 'none'`: omission lets
OpenAI choose its default, whereas `none` explicitly requests no reasoning on
models that support it.

`max_output_tokens` covers both reasoning and visible output. Allocate sufficient
headroom when increasing effort, especially for JSON responses. The legacy
`max_tokens` option is still accepted and mapped to `max_output_tokens`.

## Supported Models

`chat`, `responses`, and `chat_stream` use `/v1/responses`.
They do not use the legacy Chat Completions endpoint, and returned content is in
`output`, not `choices`.

Model IDs are passed to OpenAI without a model allowlist. Examples include:

- `gpt-5.5`
- `gpt-5.4-mini`
- `gpt-5`, `gpt-5-mini`
- `gpt-4.1`, `gpt-4o`, `gpt-4o-mini` (the gem's default model)

Availability depends on your account and each model's Responses API support.
Check the [OpenAI model catalog](https://developers.openai.com/api/docs/models)
for current model IDs and supported parameters.

### GPT-6 / GPT-6.1: Forward Compatibility Only

The gem accepts `gpt-6`, `gpt-6.1`, and their family-style model IDs without a
client update, and applies the configurable reasoning default to them.
**These IDs are covered by mocked request-serialization tests only.**
Their official model documentation was unavailable when this support was added;
no live GPT-6 or GPT-6.1 API compatibility has been verified.

If OpenAI makes those models available, use the published model ID and supported
parameters. If a model requires its API default rather than the gem's reasoning
default, pass `reasoning: nil`.

## Configuration and Rails

In Rails, place this configuration in `config/initializers/chatgpt.rb`:

```ruby
require 'chatgpt'

ChatGPT.configure do |config|
  config.api_key = Rails.application.credentials.chatgpt_api_key
  config.default_engine = 'gpt-5.5'
  config.reasoning_effort = 'medium'
  config.open_timeout = 5
  config.request_timeout = 60
  config.max_retries = 2
  config.default_parameters = { max_output_tokens: 8000 }
end
```

Outside Rails, use `ENV.fetch('OPENAI_API_KEY')` for the key. An explicit key and
model can also be supplied to `ChatGPT::Client.new(api_key, model)`.
Increasing reasoning effort may require a longer request timeout.

## Streaming

```ruby
client.chat_stream(messages, reasoning_effort: 'medium', max_output_tokens: 8000) do |event|
  print event['delta'] if event['type'] == 'response.output_text.delta'
end
```

## Response Metadata and JSON Output

`chat` returns the parsed response body. Use `responses` for status, headers, and
the OpenAI request ID:

```ruby
response = client.responses(
  messages,
  reasoning_effort: 'medium',
  max_output_tokens: 8000,
  text: { format: { type: 'json_object' } },
  store: false
)

puts response.request_id
puts response.status
puts response.body
```

When requesting JSON output, instruct the model to produce JSON in your messages.
The native `text` object also supports JSON Schema output formats.

## Error Handling

```ruby
begin
  response = client.chat(messages)
rescue ChatGPT::AuthenticationError => e
  warn "Authentication error: #{e.message}"
rescue ChatGPT::RateLimitError => e
  warn "Rate limit exceeded: #{e.message}"
rescue ChatGPT::InvalidRequestError => e
  warn "Invalid request: #{e.message}"
rescue ChatGPT::TimeoutError => e
  warn "Request timed out: #{e.message}"
rescue ChatGPT::APIError => e
  warn "OpenAI API error: #{e.message}"
end
```

Non-streaming requests retry connection failures, timeouts, HTTP 408/409/429, and
5xx responses up to `max_retries`, honoring `Retry-After` within the retry delay cap.
Streaming requests do not automatically retry.

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

The test suite stubs HTTP requests; it does not verify live model availability.

## Contributing

Open issues and pull requests at
[andyklimczak/chatgpt-ruby](https://github.com/andyklimczak/chatgpt-ruby).
See [CHANGELOG.md](CHANGELOG.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](LICENSE.txt). Original copyright and attribution
are retained.
