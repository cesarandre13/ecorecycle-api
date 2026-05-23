defmodule EcorecycleApiWeb.AuthController do

  use EcorecycleApiWeb, :controller

  alias Ecto.Adapters.SQL
  alias EcorecycleApi.Repo

  # =========================
  # REGISTER
  # =========================
 def register(conn, params) do

  name =
    params["name"]

  email =
    params["email"]

  password =
    params["password"]

  unit_management =
    params["UnitManagement"]

  query = """
  INSERT INTO users
  (
    name,
    email,
    password,
    UnitManagement
  )
  VALUES
  (
    @1,
    @2,
    @3,
    @4
  )
  """

  Ecto.Adapters.SQL.query!(
    EcorecycleApi.Repo,
    query,
    [
      name,
      email,
      password,
      unit_management
    ]
  )

  json(conn, %{
    success: true
  })
end

  # =========================
  # LOGIN
  # =========================
def login(conn, params) do

  email =
    params["email"]

  password =
    params["password"]

  query = """
  SELECT

    U.Id,
    U.Name,
    U.Email,
    R.Nombre AS Rol,
    U.UnitManagement,
    U.eco_points,
    NE.NombreNivel,
        NE.Id

  FROM users U

  INNER JOIN Roles R
    ON U.RolId = R.Id

  LEFT JOIN NivelesEco NE
    ON U.eco_points BETWEEN NE.PuntosMinimos
    AND NE.PuntosMaximos

  WHERE U.Email = @1
    AND U.Password = @2
  """

  result =
    Ecto.Adapters.SQL.query!(
      EcorecycleApi.Repo,
      query,
      [
        email,
        password
      ]
    )

  if length(result.rows) > 0 do

    row =
      List.first(result.rows)

    eco_points =
      Enum.at(row, 5) || 0

    nivel =
      Enum.at(row, 6) || "Semilla"

    json(conn, %{
      success: true,

      user: %{
        id: Enum.at(row, 0),
        name: Enum.at(row, 1),
        email: Enum.at(row, 2),
        rol: Enum.at(row, 3),
        UnitManagement: Enum.at(row, 4),

        eco_points: eco_points,

        nivel: nivel,
        idlevel: Enum.at(row, 7)
      }
    })

  else

    json(conn, %{
      success: false,
      message: "Usuario o contraseña incorrectos"
    })

  end
end
end