# GeminiCompletions Rails (WIP)

A basic wrapper for the Google Gemini API with support for function calling and tools and streaming in Rails.

⚠️ This gem is still under development and not available as a gem yet. ⚠️

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'gemini-completions-rails', git: 'https://github.com/gabriel-dehan/gemini_completions.git'
```

And then execute:
```bash
$ bundle install
```

Then use it in your application:

```ruby
# Initialize the client
client = GeminiCompletions::Client.new(api_key, model: "gemini-2.0-flash", stream: true)

# Simple text generation
response = client.generate_content([
  { role: "user", parts: [{ text: "Hello!" }] }
])
```

The gem comes with two big components:
- `GeminiCompletions::Client`, a client for the Gemini API, that can be used as a standalone client
- `GeminiCompletions::Streamer`, a class to handle the streaming of the response in your Rails controllers

## Gemini Completions Client

### Creating a client

```ruby
client = GeminiCompletions::Client.new(api_key, model: "gemini-2.0-flash", stream: true)
```

#### Configuration Options

- `api_key`: The API key to use for the client
- `model`: The model to use for the client, see [Gemini API models](https://ai.google.dev/gemini-api/docs/models) for available models
- `stream`: Whether to stream completions generated from this client, defaults to `false`

### Generating Content

Generating content is done by calling the `generate_content` method on the client.

```ruby
# Generate content
response = client.generate_content([
  { role: "user", parts: [{ text: "Hello!" }] }
])
```

This will return a response from the Gemini API, like this:

```ruby
{
  "candidates" => [
    {
      "content" => {
        "parts" => [
          {
            "text" => "Hello! How can I help you today?\n"
          }
        ],
        "role" => "model"
      },
      "finishReason" => "STOP",
      "avgLogprobs" => -0.07568919658660889
    }
  ],
  "usageMetadata" => {
    "promptTokenCount" => 2,
    "candidatesTokenCount" => 10,
    "totalTokenCount" => 12,
    "promptTokensDetails" => [
      {
        "modality" => "TEXT",
        "tokenCount" => 2
      }
    ],
    "candidatesTokensDetails" => [
      {
        "modality" => "TEXT",
        "tokenCount" => 10
      }
    ]
  },
  "modelVersion" => "gemini-2.0-flash"
}
```

####  Configuration Options

When generating content, you can pass the following options:

| Option | Type | Description |
|--------|------|-------------|
| `system_instructions` | String | System instructions for the model (custom prompt) |
| `tools` | Array | Array of tool classes for function calling |
| `temperature` | Float | Controls randomness of the output (0.0 to 1.0) |
| `max_output_tokens` | Integer | Maximum tokens to generate |

### Streaming the response

To stream the response, you first need to initialize the client with `stream: true`:

```ruby
client = GeminiCompletions::Client.new(api_key, model: "gemini-2.0-flash", stream: true)
```

Then you can pass a block to the `generate_content` method:

```ruby
client.generate_content([
  { role: "user", parts: [{ text: "Tell me a long story about dragons" }] }
]) do |chunk|
  # Each chunk's format is the same as the non-streaming response from the API, with candidates and usageMetadata
  puts chunk
end
```

## GeminiCompletions Streamer

If you want to stream the response from the client in your Rails controllers, you can use the `GeminiCompletions::Streamer` class.

One very essential thing is to `include ActionController::Live` in your controller. Without that the chunks will still be sent one by one to the callback block, but it will wait for the end of the response before sending anything to the client.

```ruby
class ChatController < ApplicationController
  include ActionController::Live

  def completions
    # ...
  end
end
```

### Usage

```ruby
# Don't forget to initialize the client with stream: true
client = GeminiCompletions::Client.new(api_key, model: "gemini-2.0-flash", stream: true)

# Create a streamer instance, and pass it the client and the controller's response object
streamer = GeminiCompletions::Streamer.new(client, response)

options = {
  systemInstruction: "You speak like a pirate.",
  tools: [CustomTools::ScheduleMeeting]
}

# Start the completion and stream back the chunks to the client
streamer.stream_completion([
  { role: "user", parts: [{ text: "Tell me a long story about a lonely dragon" }] }
], options) do |streamer, text|
  # This block is called when all chunks have been sent
  # The text is the full response's text

  @conversation.messages.create!(content: text)
end
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `contents` | Array | The contents of the conversation |
| `options` | Hash | The same options you would pass to client.generate_content() |
| `&on_done_block` | Proc | A block or proc that will be called when the completion is done and all chunks have been sent |


## Function Calling / Tools

You can provide tools to the model for it to use at its own discretion before sending the response back to the user.
Example of such tools are for instance a tool to get data from the database, make a call to an external API, etc...

### Defining a Tool

Tools are defined by inheriting from `GeminiCompletions::Tool`.
Each tool needs to be defined with the following parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | String | The name of the tool, should be unique and always in underscore case. |
| `description` | String | The description of the tool, this explains to the model what the tool does.  |
| `parameters` | Hash | The parameters schema of the tool, see below for the supported types. |
| `handler` | Proc | The code to be executed when the tool is called, it should return a hash with the tool's response. |

Check [The Function Declaration documentation](https://ai.google.dev/api/caching#FunctionDeclaration) for more information on how to define tools.


```ruby
module CustomTools
  class ScheduleMeeting < GeminiCompletions::Tool
    name "schedule_meeting"
    description "Schedules a meeting with specified attendees at a given time and date."
    parameters({
      type: "object",
      properties: {
        attendees: {
          type: "array",
          items: { type: "string" },
          description: "List of people attending the meeting."
        },
        date: {
          type: "string",
          description: "Date of the meeting (e.g., '2024-07-29')"
        },
        time: {
          type: "string",
          description: "Time of the meeting (e.g., '15:00')"
        },
        topic: {
          type: "string",
          description: "The subject or topic of the meeting."
        }
      },
      required: ["attendees", "date", "time", "topic"]
    })

    handler do |params|
      puts "Scheduling meeting with: #{params}"

      event = Event.create!(
        attendees: params[:attendees],
        date: params[:date],
        time: params[:time],
        topic: params[:topic]
      )

      # Return a hash with the data that will be sent to the model
      {
        event_id: event.id,
        date: event.date,
        time: event.time,
        topic: event.topic,
        attendees: event.attendees
      }
    end
  end
end
```

#### Retrieving defined tools

You can retrieve the tools by calling:

```ruby
# Get all tools
tools = GeminiCompletions::Tool.all

# Get a tool by name
tool = GeminiCompletions::Tool.find_by_name("schedule_meeting")

# Call the tool (execute the handler block)
result = tool.call({ attendees: ["John Doe", "Jane Smith"], date: "2024-07-29", time: "15:00", topic: "Q3 Planning" })
```

### Using tools with the Client

When calling the `generate_content` method with Tools, the Gemini API will return a `functionCall` in the response instead of just `text` parts.


```ruby
response = client.generate_content([
  { role: "user", parts: [{ text: "Schedule a meeting with Bob and Alice tomorrow at 3pm about Q3 planning" }] }
], tools: [CustomTools::ScheduleMeeting])
```

The response will look like this:

```ruby
{
  "candidates" => [
    {
      "content" => {
        "parts" => [
          {
            "text" => "Let me check if I can schedule that meeting..."
          },
          {
            "functionCall" => {
              "name" => "schedule_meeting",
              "args" => {
                "attendees" => ["John Doe", "Jane Smith"],
                "date" => "2024-07-29",
                "time" => "15:00",
                "topic" => "Q3 Planning"
              }
            }
          }
        ],
        "role" => "model"
      },
      # ...
    }
  ],
  # ...
}
```

The `functionCall` part contains all you need to execute the tool.

#### Handling the response

You can handle the response by checking if there is a `functionCall` part in the response, and if there is, execute the tool.

```ruby
contents = [
  {
    role: "user",
    parts: [{ text: "Schedule a meeting with Bob and Alice tomorrow at 3pm about Q3 planning" }]
  }
]
response = client.generate_content(contents, tools: [CustomTools::ScheduleMeeting])

# Add the model's response that will be sent for the next generation
contents << response

# Handle the response
function_call = response.dig('candidates', 0, 'content', 'parts', 0, 'functionCall')
if function_call
  tool_name = function_call['name']
  args = function_call['args']

  # Find and execute the tool
  tool = GeminiCompletions::Tool.find_by_name(tool_name)
  result = tool.call(args)

  # Provide the result in the next chat message, setting it in a functionResult part
  contents << {
    role: "user",
    parts: [{
      functionResponse: {
        name: tool_name,
        response: {
          result: result
        }
      }
    }]
  }
end

# Continue the conversation with the updated contents
response = client.generate_content(contents, tools: [CustomTools::ScheduleMeeting])

# The model will respond that it has scheduled the meeting, etc...
```

### Using tools with the completions streamer

The completions streamer handles everything on its own:
- If a tool is called it will be executed and the result will be provided to the model in the next message.
- It handles multi-turn tool calls automatically, meaning that is multiple tools must be made in succession, it will be done so without you having to do anything.
- It will also handle parallel tool calls, meaning that if two tools are called at the same time, it will execute them at the same time and provide the results to the model in the next message.

It does this while streaming the response directly to the client, sending an `executed_tools` event to the client every time a tool is executed.


```ruby
client = GeminiCompletions::Client.new(ENV.fetch("GEMINI_API_KEY"), model: "gemini-2.0-flash", stream: true)
streamer = GeminiCompletions::Streamer.new(client, response)

options = {
  systemInstruction: "You speak like a pirate.",
  tools: [CustomTools::ScheduleMeeting]
}

contents = [
  { role: "user", parts: [{ text: "Schedule a meeting with Bob and Alice tomorrow at 3pm about Q3 planning" }] }
]

streamer.stream_completion(contents, options) do |streamer, text|
  # This block is called when all chunks have been sent and all tool calls have been executed
  @conversation.messages.create!(content: text)
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gabriel-dehan/gemini-completions-rails.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).