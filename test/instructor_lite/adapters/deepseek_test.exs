defmodule InstructorLite.Adapters.DeepseekTest do
  use ExUnit.Case, async: true
  import Mox
  alias InstructorLite.Adapters.Deepseek
  alias InstructorLite.TestSchemas.SpamPrediction
  alias InstructorLite.HTTPClient

  setup :verify_on_exit!

  describe "send_request/2" do
    test "returns parsed response on success" do
      params = %{
        messages: [
          %{role: "user", content: "Test message"}
        ]
      }

      opts = [
        adapter_context: [
          api_key: "test_key",
          model: "deepseek-chat",
          http_options: [],
          http_client: HTTPClient.Mock
        ],
        response_model: SpamPrediction,
        json_schema: %{}
      ]

      expect(HTTPClient.Mock, :post, fn url, opts ->
        assert url == "https://api.deepseek.com/chat/completions"
        assert opts[:json] == params
        assert opts[:auth] == {:bearer, "test_key"}

        {:ok,
         %{
           status: 200,
           body: "response"
         }}
      end)

      assert {:ok, "response"} =
               Deepseek.send_request(params, opts)
    end

    test "returns error on API error response" do
      params = %{
        messages: [
          %{role: "user", content: "Test message"}
        ]
      }

      opts = [
        adapter_context: [
          api_key: "test_key",
          http_options: [],
          http_client: HTTPClient.Mock
        ],
        response_model: SpamPrediction,
        json_schema: %{}
      ]

      expect(HTTPClient.Mock, :post, fn _, _ ->
        {:ok,
         %{
           status: 400,
           body: %{
             "error" => %{
               "message" => "Invalid API key"
             }
           }
         }}
      end)

      assert {:error, %{status: 400, body: %{"error" => %{"message" => "Invalid API key"}}}} =
               Deepseek.send_request(params, opts)
    end
  end

  describe "parse_response/2" do
    test "parses valid response" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "{\"class\":\"spam\",\"score\":0.85}"
            }
          }
        ]
      }

      assert {:ok, %{"class" => "spam", "score" => 0.85}} =
               Deepseek.parse_response(response, [])
    end

    test "returns error on unexpected response format" do
      response = %{
        "invalid" => "format"
      }

      assert {:error, :unexpected_response, _} =
               Deepseek.parse_response(response, [])
    end
  end

  describe "initial_prompt/2" do
    test "includes mandatory and optional notes" do
      params = %{messages: []}
      opts = [notes: "Test notes", response_model: SpamPrediction, json_schema: %{}]

      result = Deepseek.initial_prompt(params, opts)

      assert result.messages == [
               %{
                 role: "system",
                 content: """
                 As a genius expert, your task is to understand the content and provide the parsed objects in json that match json schema

                 json_schema:
                 {}
                 Additional notes on the schema:
                 Test notes
                 """
               }
             ]
    end
  end

  describe "retry_prompt/2" do
    test "includes validation errors in retry prompt" do
      params = %{messages: []}
      resp_params = %{foo: "bar"}
      errors = "Validation errors"
      opts = [response_model: SpamPrediction, model: "deepseek-chat", json_schema: %{}]

      result = Deepseek.retry_prompt(params, resp_params, errors, %{}, opts)

      assert result.messages == [
               %{role: "assistant", content: "{\"foo\":\"bar\"}"},
               %{
                 role: "system",
                 content: """
                 The response did not pass validation. Please try again and fix the following validation errors:

                 Validation errors
                 """
               }
             ]
    end
  end
end
