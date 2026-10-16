## [Unreleased]

### Added
- Global `config.reasoning_effort` and per-request `reasoning_effort` for chat, responses, and streaming.
- Native reasoning defaults through `config.default_parameters[:reasoning]`, with per-request overrides and explicit omission via `nil`.
- Forward-compatible GPT-6/GPT-6.1 model-ID handling, covered by mocked tests only; live API support is unverified.

### Fixed
- Honor `max_output_tokens` in configured default parameters, including configurations without `max_tokens`.

### Changed
- Rebase the GPT-5 branch onto the original upstream's `main`, preserving the fork's Responses API and transport changes.
- Document GPT-5 models, thinking controls, and the limits of GPT-6 compatibility; point installation and repository links to this fork.

## [2.1.1] - 2024-04-19

### Fixed
- Use configured default_engine in chat methods instead of hardcoded 'gpt-3.5-turbo'
- Add Rails integration with proper Railtie for automatic GPT inflection

## [2.1.0] - 2025-01-30

### Changed
- Updated model support for GPT-3.5-turbo and GPT-3.5-turbo-instruct
- Fixed configuration module
- Improved error handling
- Updated documentation and Wiki

### Added
- Support for chat and completions APIs
- Streaming support
- Comprehensive test coverage
- Better error classification

## [2.0.0] - 2023-07-08

### Added

- Added support for chat interactions with the GPT-3.5-turbo model.
- Introduced a new `chat` method to the `ChatGPT::Client` class, which sends an array of chat messages to the API and receives the generated messages in return.
- Updated the README to provide usage instructions for the new `chat` method.

## [1.0.0] - 2023-04-30

### Added

- Initial release of the `chatgpt-ruby` gem.
- Implements ChatGPT Client with methods for completions, search, classification, summary, and answer generation.
- Includes unit tests for each method.

## [0.1.0] - 2023-03-22

- Initial release
