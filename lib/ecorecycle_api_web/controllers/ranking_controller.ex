defmodule EcorecycleApiWeb.RankingController do

  use EcorecycleApiWeb, :controller

  alias EcorecycleApi.Repo

  def ranking(conn, _params) do

    result =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT TOP 50

          name,

          eco_points,

          co2_saved,

          UnitManagement

        FROM users

        ORDER BY eco_points DESC
        """
      )

    columns = result.columns

    data =
      Enum.map(result.rows, fn row ->

        Enum.zip(columns, row)
        |> Enum.into(%{})

      end)

    json(conn, %{
      success: true,
      ranking: data
    })
  end
end