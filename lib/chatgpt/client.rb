# frozen_string_literal: true

# lib/chatgpt/client.rb
require 'rest-client'
require 'json'
require 'time'

module ChatGPT
  class Client
    Response = Struct.new(:body, :status, :headers, :request_id, keyword_init: true)

    RETRYABLE_STATUS_CODES = [408, 409, 429].freeze
    RETRY_DELAY_CAP = 30.0

    def initialize(api_key = nil, model = nil, transport: RestClient::Request, sleeper: ->(seconds) { sleep(seconds) }, jitter: -> { rand })
      @api_key = api_key || ChatGPT.configuration.api_key
      @endpoint = 'https://api.openai.com/v1'
      @config = ChatGPT.configuration
      @default_model = model || @config.default_engine
      @transport = transport
      @sleeper = sleeper
      @jitter = jitter
    end

    def completions(prompt, params = {})
      engine = params[:engine] || @default_model
      url = "#{@endpoint}/engines/#{engine}/completions"

      data = @config.default_parameters.merge(
        prompt: prompt,
        max_tokens: params[:max_tokens],
        temperature: params[:temperature],
        top_p: params[:top_p],
        n: params[:n]
      ).compact

      request_api(url, data)
    end

    def chat(messages, params = {})
      responses(messages, params).body
    end

    def responses(messages, params = nil, before_request: nil, **keyword_params)
      params = (params || {}).merge(keyword_params)
      model = resolve_model(params)
      url = "#{@endpoint}/responses"
      data = responses_payload(messages, params, model)

      request_response(url, data, before_request: before_request)
    end

    def chat_stream(messages, params = {}, &block)
      raise ArgumentError, 'Block is required for streaming' unless block_given?

      model = resolve_model(params)
      url = "#{@endpoint}/responses"
      data = responses_payload(messages, params.merge(stream: true), model)

      request_streaming(url, data, &block)
    end

    private

    def resolve_model(params)
      params[:model] || @default_model
    end

    def responses_payload(messages, params, model)
      defaults = @config.default_parameters
      default_max_output_tokens = [defaults[:max_output_tokens] || defaults[:max_tokens] || 128, 128].max
      payload = {
        model: model,
        input: messages,
        max_output_tokens: params[:max_output_tokens] || params[:max_tokens] || default_max_output_tokens,
        stream: params[:stream] || false
      }
      if params.key?(:reasoning)
        payload[:reasoning] = params[:reasoning]
      elsif params.key?(:reasoning_effort)
        payload[:reasoning] = { effort: params[:reasoning_effort] } unless params[:reasoning_effort].nil?
      elsif defaults.key?(:reasoning)
        payload[:reasoning] = defaults[:reasoning]
      elsif reasoning_supported?(model) && @config.reasoning_effort
        payload[:reasoning] = { effort: @config.reasoning_effort }
      end
      payload[:text] = params[:text] if params.key?(:text)
      payload[:temperature] = params[:temperature] if params.key?(:temperature)
      payload[:top_p] = params[:top_p] if params.key?(:top_p)
      payload[:store] = params[:store] if params.key?(:store)
      payload[:safety_identifier] = params[:safety_identifier] if params.key?(:safety_identifier)
      validate_safety_identifier!(payload[:safety_identifier]) if payload.key?(:safety_identifier)
      payload.compact
    end

    def request_api(url, data)
      request_response(url, data).body
    end

    def request_response(url, data, before_request: nil)
      attempts = 0

      begin
        attempts += 1
        options = request_options(url, data)
        before_request&.call(options[:payload])
        response = @transport.execute(options)
        headers = normalized_headers(response.headers)

        Response.new(
          body: JSON.parse(response.body),
          status: response.code,
          headers: headers,
          request_id: headers['x-request-id']
        )
      rescue RestClient::Exceptions::Timeout, Errno::ETIMEDOUT
        if retry_request?(attempts)
          sleep_for_retry(attempts)
          retry
        end

        raise ChatGPT::TimeoutError, 'The OpenAI request timed out.'
      rescue RestClient::ExceptionWithResponse => e
        if retry_request?(attempts, e)
          sleep_for_retry(attempts, e)
          retry
        end

        handle_error(e)
      rescue RestClient::Exception, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET
        if retry_request?(attempts)
          sleep_for_retry(attempts)
          retry
        end

        raise ChatGPT::APIError, 'The OpenAI request could not be completed.'
      end
    end

    def reasoning_supported?(model)
      model.to_s.match?(/\Agpt-(?:5|6)(?:[.-]|\z)/)
    end

    def handle_error(error)
      error_response = JSON.parse(error.response.body)
      error_message = error_response.dig('error', 'message') || 'The OpenAI request was rejected.'
      status_code = error.response.code

      case status_code
      when 401
        raise ChatGPT::AuthenticationError.new(error_message, status_code)
      when 429
        raise ChatGPT::RateLimitError.new(error_message, status_code)
      when 400
        raise ChatGPT::InvalidRequestError.new(error_message, status_code)
      else
        raise ChatGPT::APIError.new(error_message, status_code)
      end
    end

    def request_options(url, data)
      { headers: {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json'
        },
        method: :post,
        payload: data.to_json,
        stream_to_buffer: true,
        open_timeout: @config.open_timeout,
        timeout: @config.request_timeout,
        url: url }
    end

    def retry_request?(attempts, error = nil)
      return false if attempts > @config.max_retries
      return true unless error

      status_code = error.response.code
      RETRYABLE_STATUS_CODES.include?(status_code) || status_code >= 500
    end

    def sleep_for_retry(attempts, error = nil)
      @sleeper.call(retry_delay(attempts, error))
    end

    def retry_delay(attempts, error)
      retry_after = retry_after_seconds(error)
      base_delay = [0.5 * (2**(attempts - 1)), RETRY_DELAY_CAP].min
      delay = retry_after || base_delay

      [delay + (@jitter.call * 0.25), RETRY_DELAY_CAP].min
    end

    def retry_after_seconds(error)
      return unless error

      value = normalized_headers(error.response.headers)['retry-after']
      return unless value

      numeric = Float(value) rescue nil
      return numeric if numeric

      timestamp = Time.httpdate(value) rescue nil
      timestamp && [timestamp - Time.now, 0].max
    end

    def normalized_headers(headers)
      headers.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s.tr('_', '-').downcase] = value.to_s
      end
    end

    def validate_safety_identifier!(identifier)
      return if identifier.match?(/\Av\d{1,6}\.[A-Za-z0-9_-]{43}\z/)

      raise ArgumentError, 'safety_identifier must be a versioned, URL-safe HMAC digest'
    end

    def request_streaming(url, data)
      RestClient::Request.execute(request_options(url, data)) do |chunk, _x, _z|
        chunk.split("\n").filter { |c| c.start_with?('data:') }.each do |line|
          data = line.sub(/^data: /, '')
          next if data.strip == '[DONE]'

          begin
            parsed = JSON.parse(data)
            yield parsed if block_given?
          rescue JSON::ParserError
            next
          end
        end
      end
    rescue RestClient::ExceptionWithResponse => e
      handle_error(e)
    end
  end
end
