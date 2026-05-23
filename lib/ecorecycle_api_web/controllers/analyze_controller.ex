defmodule EcorecycleApiWeb.AnalyzeController do
  use EcorecycleApiWeb, :controller

  def analyze(conn, %{"file" => %Plug.Upload{path: path}}) do
  case HTTPoison.post(
         "http://192.168.1.36:8001/analyze",
         {:multipart, [{:file, path}]}
       ) do

    {:ok, response} ->
      case Jason.decode(response.body) do
        {:ok, json} ->
          json(conn, json)

        {:error, _} ->
          json(conn, %{error: "Respuesta no es JSON válido"})
      end

    {:error, error} ->
      json(conn, %{error: "Error conectando a IA", detail: inspect(error)})
  end
end
end