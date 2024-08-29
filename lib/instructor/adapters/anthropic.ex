defmodule Instructor.Adapters.Anthropic do
  @moduledoc """
  Documentation for `Instructor.Adapters.Anthropic`
  """
  @behaviour Instructor.Adapter

  @default_model "claude-3-5-sonnet-20240620"
  @default_max_tokens 1024

  @send_request_schema NimbleOptions.new!(
                         api_key: [
                           type: :string,
                           required: true,
                           doc: "Anthropic API key"
                         ],
                         http_client: [
                           type: :atom,
                           default: Req,
                           doc: "Any module that follows `Req.post/2` interface"
                         ],
                         http_options: [
                           type: :keyword_list,
                           default: [receive_timeout: 60_000]
                         ],
                         url: [
                           type: :string,
                           default: "https://api.anthropic.com/v1/messages",
                           doc: "API endpoint to use for sending requests"
                         ],
                         version: [
                           type: :string,
                           default: "2023-06-01",
                           doc:
                             "Anthropic [API version](https://docs.anthropic.com/en/api/versioning)"
                         ]
                       )

  @impl Instructor.Adapter
  def send_request(params, opts) do
    context =
      opts
      |> Keyword.get(:adapter_context, [])
      |> NimbleOptions.validate!(@send_request_schema)

    headers = [
      {"x-api-key", context[:api_key]},
      {"anthropic-version", context[:version]}
    ]

    options =
      context[:http_options]
      |> Keyword.merge(json: params)
      |> Keyword.update(:headers, headers, fn client_side ->
        Enum.uniq_by(client_side ++ headers, &elem(&1, 0))
      end)

    case context[:http_client].post(context[:url], options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Instructor.Adapter
  def initial_prompt(params, opts) do
    mandatory_part = """
    As a genius expert, your task is to understand the content and provide the parsed objects in json that match json schema\n
    """

    optional_notes =
      if notes = opts[:notes] do
        """
        Additional notes on the schema:\n
        #{notes}
        """
      else
        ""
      end

    params
    |> Map.put_new(:model, @default_model)
    |> Map.put_new(:max_tokens, @default_max_tokens)
    |> Map.put_new(:system, mandatory_part <> optional_notes)
    |> Map.put_new(:tool_choice, %{type: "tool", name: "Schema"})
    |> Map.put_new(:tools, [
      %{
        name: "Schema",
        description:
          "Correctly extracted `Schema` with all the required parameters with correct types",
        input_schema: Keyword.fetch!(opts, :json_schema)
      }
    ])
  end

  @impl Instructor.Adapter
  def retry_prompt(params, _resp_params, errors, response, _opts) do
    %{"content" => [%{"id" => tool_use_id}]} =
      assistant_reply = Map.take(response, ["content", "role"])

    do_better = [
      assistant_reply,
      %{
        role: "user",
        content: [
          %{
            type: "tool_result",
            tool_use_id: tool_use_id,
            is_error: true,
            content: """
            Validation failed. Please try again and fix following validation errors

            #{errors}
            """
          }
        ]
      }
    ]

    Map.update(params, :messages, do_better, fn msgs -> msgs ++ do_better end)
  end

  @impl Instructor.Adapter
  def parse_response(response, _opts) do
    case response do
      %{"stop_reason" => "tool_use", "content" => [%{"input" => decoded}]} ->
        {:ok, decoded}

      other ->
        {:error, :unexpected_response, other}
    end
  end
end
