defmodule Instructor.Adapters.Llamacpp do
  @moduledoc """
  Runs against the llama.cpp server. To be clear this calls the llamacpp specific
  endpoints, not the open-ai compliant ones.

  You can read more about it here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server
  """

  @behaviour Instructor.Adapter

  @default_config [
    url: "http://localhost:8000/completion",
    http_options: [receive_timeout: 60_000]
  ]

  @doc """
  Run a completion against the llama.cpp server, not the open-ai compliant one.
  This gives you more specific control over the grammar, and the ability to
  provide other parameters to the specific LLM invocation.

  You can read more about the parameters here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server

  ## Examples

    iex> Instructor.chat_completion(
    ...>   model: "mistral-7b-instruct",
    ...>   messages: [
    ...>     %{ role: "user", content: "Classify the following text: Hello I am a Nigerian prince and I would like to send you money!" },
    ...>   ],
    ...>   response_model: response_model,
    ...>   temperature: 0.5,
    ...> )
  """
  @impl true
  def chat_completion(params, opts) do
    opts = Keyword.merge(@default_config, opts)
    http_client = Keyword.fetch!(opts, :http_client)
    url = Keyword.fetch!(opts, :url)

    options = Keyword.merge(opts[:http_options], json: params)

    case http_client.post(url, options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def initial_prompt(json_schema, params) do
    params
    |> Map.put_new(:json_schema, json_schema[:schema])
    |> Map.put_new(:system_prompt, """
    As a genius expert, your task is to understand the content and provide the parsed objects in json that match json_schema
    """)
  end

  @impl true
  def retry_prompt(params, resp_params, errors) do
    do_better = """
    Your previous response:

    #{Jason.encode!(resp_params)}

    did not pass validation. Please try again and fix following validation errors:\n
    #{errors}
    """

    params
    |> Map.update(:prompt, do_better, fn prompt ->
      prompt <> "\n" <> do_better
    end)
  end

  @impl true
  def from_response(response) do
    case response do
      %{"content" => json} ->
        Jason.decode(json)

      other ->
        {:error, :unexpected_response, other}
    end
  end
end
