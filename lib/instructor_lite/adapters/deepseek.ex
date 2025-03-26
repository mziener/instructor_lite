defmodule InstructorLite.Adapters.Deepseek do
  @moduledoc """
  Deepseek adapter following the guidelines provided [here](https://api-docs.deepseek.com/guides/json_mode)

  ## Example

  ```
  InstructorLite.instruct(%{
      messages: [%{role: "user", content: "John is 25yo"}],
      model: "deepseek-chat",
    },
    response_model: %{name: :string, age: :integer},
    adapter: InstructorLite.Adapters.Deepseek,
    adapter_context: [api_key: Application.fetch_env!(:instructor_lite, :deepseek_key)]
  )
  {:ok, %{name: "John", age: 25}}
  ```
  """
  @behaviour InstructorLite.Adapter

  @default_model "deepseek-chat"

  @send_request_schema NimbleOptions.new!(
                         api_key: [
                           type: :string,
                           required: true,
                           doc: "Deepseek API key"
                         ],
                         http_client: [
                           type: :atom,
                           default: Req,
                           doc: "Any module that follows `Req.post/2` interface"
                         ],
                         http_options: [
                           type: :keyword_list,
                           default: [receive_timeout: 60_000],
                           doc: "Options passed to `http_client.post/2`"
                         ],
                         url: [
                           type: :string,
                           default: "https://api.deepseek.com/chat/completions",
                           doc: "API endpoint to use for sending requests"
                         ],
                         model: [
                           type: :string,
                           default: "deepseek-chat",
                           doc: "The model to use"
                         ]
                       )

  @doc """
  Make request to Deepseek API.
    
  ## Options

  #{NimbleOptions.docs(@send_request_schema)}
  """
  @impl InstructorLite.Adapter
  def send_request(params, opts) do
    context =
      opts
      |> Keyword.get(:adapter_context, [])
      |> NimbleOptions.validate!(@send_request_schema)

    options =
      Keyword.merge(context[:http_options], json: params, auth: {:bearer, context[:api_key]})

    case context[:http_client].post(context[:url], options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates `params` with prompt based on `json_schema` and `notes`.

  Also specifies default `#{@default_model}` model if not provided by a user. 
  """
  @impl InstructorLite.Adapter
  def initial_prompt(params, opts) do
    mandatory_part = """
    As a genius expert, your task is to understand the content and provide the parsed objects in json that match json schema

    json_schema:
    #{Keyword.fetch!(opts, :json_schema) |> Jason.encode!()}
    """

    optional_notes =
      if notes = opts[:notes] do
        """
        Additional notes on the schema:
        #{notes}
        """
      else
        ""
      end

    sys_message = [
      %{
        role: "system",
        content: mandatory_part <> optional_notes
      }
    ]

    params
    |> Map.put_new(:model, @default_model)
    |> Map.put_new(:response_format, %{
      type: "json_object"
    })
    |> Map.update(:messages, sys_message, fn msgs -> sys_message ++ msgs end)
  end

  @doc """
  Updates `params` with prompt for retrying a request.
  """
  @impl InstructorLite.Adapter
  def retry_prompt(params, resp_params, errors, _response, _opts) do
    do_better = [
      %{role: "assistant", content: Jason.encode!(resp_params)},
      %{
        role: "system",
        content: """
        The response did not pass validation. Please try again and fix the following validation errors:

        #{errors}
        """
      }
    ]

    Map.update(params, :messages, do_better, fn msgs -> msgs ++ do_better end)
  end

  @doc """
  Parse chat completion endpoint response.

  Can return:
    * `{:ok, parsed_json}` on success.
    * `{:error, :refusal, reason}` on [refusal].
    * `{:error, :unexpected_response, response}` if response is of unexpected shape.
  """
  @impl InstructorLite.Adapter
  def parse_response(response, _opts) do
    case response do
      %{"choices" => [%{"message" => %{"content" => json}}]} ->
        Jason.decode(json)

      %{"choices" => [%{"message" => %{"refusal" => refusal}}]} ->
        {:error, :refusal, refusal}

      other ->
        {:error, :unexpected_response, other}
    end
  end
end
