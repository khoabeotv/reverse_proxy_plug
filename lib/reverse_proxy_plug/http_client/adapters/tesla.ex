if Code.ensure_loaded?(Tesla) do
  defmodule ReverseProxyPlug.HTTPClient.Adapters.Tesla do
    @moduledoc """
    Tesla adapter for the `ReverseProxyPlug.HTTPClient` behaviour

    Only synchronous responses are supported.

    ## Options

    * `:tesla_client` - mandatory definition for the `Tesla.Client`
                        to be used.
    """

    alias ReverseProxyPlug.HTTPClient
    alias Tesla.Multipart

    @behaviour HTTPClient

    @impl HTTPClient
    def request(%HTTPClient.Request{options: options} = request) do
      {client, opts} = Keyword.pop(options, :tesla_client)

      unless client do
        raise ":tesla_client option is required"
      end

      query_params =
        if request.query_params == %{},
          do: [],
          else: request.query_params

      request =
        if is_map(request.body) do
          # Cần drop content-type & content-length cũ vì build lại body multipart sẽ không còn chính xác nữa
          headers =
            List.keydelete(request.headers, "content-type", 0)
            |> List.keydelete("content-length", 0)

          mp =
            Enum.reduce(request.body, Multipart.new(), fn {key, el}, multipart ->
              add_multi_part(key, el, multipart)
            end)

          %{request | body: mp, headers: headers}
        else
          request
        end

      tesla_opts =
        request
        |> Map.take([:url, :method, :body, :headers])
        |> Map.put(:query, query_params)
        |> Map.put(:opts, opts)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      case Tesla.request(client, tesla_opts) do
        {:ok, %Tesla.Env{} = env} ->
          {:ok,
           %HTTPClient.Response{
             status_code: env.status,
             body: env.body,
             headers: env.headers,
             request_url: env.url,
             request: request
           }}

        {:error, error} ->
          {:error, %HTTPClient.Error{reason: error}}
      end
    end

    defp add_multi_part(key, list_el, mp) when is_list(list_el) do
      key = "#{key}[]"

      Enum.reduce(list_el, mp, fn el, acc ->
        add_multi_part(key, el, acc)
      end)
    end

    defp add_multi_part(key, el, mp) do
      case el do
        %Plug.Upload{path: path, filename: filename, content_type: content_type} ->
          Multipart.add_file(mp, path,
            name: key,
            filename: filename,
            headers: [
              {"content-type", content_type}
            ]
          )

        _ ->
          Multipart.add_field(mp, key, el)
      end
    end
  end
end
