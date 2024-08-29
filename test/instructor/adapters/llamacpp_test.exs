defmodule Instructor.Adapters.LlamacppTest do
  use ExUnit.Case, async: true

  import Mox

  alias Instructor.Adapters.Llamacpp
  alias Instructor.HTTPClient

  setup :verify_on_exit!

  describe "initial_prompt/2" do
    test "adds structured response parameters" do
      assert Llamacpp.initial_prompt(%{}, json_schema: :json_schema, notes: "Explanation") == %{
               json_schema: :json_schema,
               system_prompt: """
               As a genius expert, your task is to understand the content and provide the parsed objects in json that match json schema

               Additional notes on the schema:

               Explanation
               """
             }
    end
  end

  describe "retry_prompt/5" do
    test "appends to prompt string" do
      params = %{prompt: "Please give me test data"}

      assert Llamacpp.retry_prompt(params, %{foo: "bar"}, "list of errors", nil, []) == %{
               prompt: """
               Please give me test data
               Your previous response:

               {\"foo\":\"bar\"}

               did not pass validation. Please try again and fix following validation errors:

               list of errors
               """
             }
    end
  end

  describe "parse_response/2" do
    test "decodes json from expected output" do
      response = %{
        "content" => "{\"name\": \"George Washington\", \"birth_date\": \"1732-02-22\" }\n"
      }

      assert {:ok, %{"birth_date" => "1732-02-22", "name" => "George Washington"}} =
               Llamacpp.parse_response(response, [])
    end

    test "invalid json" do
      response = %{"content" => "{{"}

      assert {:error, %Jason.DecodeError{}} = Llamacpp.parse_response(response, [])
    end

    test "unexpected content" do
      response = "Internal Server Error"

      assert {:error, :unexpected_response, "Internal Server Error"} =
               Llamacpp.parse_response(response, [])
    end
  end

  describe "send_request/2" do
    test "overridable options" do
      params = %{hello: "world"}

      opts = [
        http_client: HTTPClient.Mock,
        http_options: [foo: "bar"],
        url: "https://localhost:8001/completion"
      ]

      expect(HTTPClient.Mock, :post, fn url, options ->
        assert url == "https://localhost:8001/completion"

        assert options == [
                 foo: "bar",
                 json: %{hello: "world"}
               ]

        {:ok, %{status: 200, body: "response"}}
      end)

      assert {:ok, "response"} = Llamacpp.send_request(params, opts)
    end

    test "non-200 response" do
      opts = [
        http_client: HTTPClient.Mock
      ]

      expect(HTTPClient.Mock, :post, fn _url, _options ->
        {:ok, %{status: 400, body: "response"}}
      end)

      assert {:error, %{status: 400, body: "response"}} = Llamacpp.send_request(%{}, opts)
    end

    test "request error" do
      opts = [
        http_client: HTTPClient.Mock
      ]

      expect(HTTPClient.Mock, :post, fn _url, _options -> {:error, :timeout} end)

      assert {:error, :timeout} = Llamacpp.send_request(%{}, opts)
    end
  end
end
