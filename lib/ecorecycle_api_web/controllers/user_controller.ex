defmodule EcorecycleApiWeb.UserController do
  use EcorecycleApiWeb, :controller

  alias EcorecycleApi.Repo

 def historial(conn, %{"id" => id}) do

  {:ok, result} =
    Ecto.Adapters.SQL.query(
      Repo,
      """
      SELECT
        sr.Id,
        sr.Estado,
        sr.FotoUrl,
        sr.FechaRegistro,
        sr.Lote,

        ISNULL(SUM(srd.Cantidad), 0) as CantidadItems,

        ISNULL(SUM(srd.Puntos), 0) as TotalPuntos,

        ISNULL(SUM(srd.Co2Ahorrado), 0) as TotalCo2,

        sr.PesoTotal

      FROM SolicitudReciclaje sr

      LEFT JOIN SolicitudReciclajeDetalle srd
        ON sr.Id = srd.SolicitudId

      WHERE sr.UsuarioId = @1

      GROUP BY
        sr.Id,
        sr.Estado,
        sr.FotoUrl,
        sr.FechaRegistro,
        sr.Lote,
        sr.PesoTotal

      ORDER BY sr.Id DESC
      """,
      [id]
    )

  historial =
    Enum.map(result.rows, fn row ->
      %{
        id: Enum.at(row, 0),
        estado: Enum.at(row, 1),
        foto_url: Enum.at(row, 2),
        fecha: Enum.at(row, 3),
        lote: Enum.at(row, 4),
        cantidad_items: Enum.at(row, 5),
        puntos: Enum.at(row, 6),
        co2: Enum.at(row, 7),
        peso_total: Enum.at(row, 8), 
      }
    end)

  json(conn, %{
    success: true,
    historial: historial
  })
end

def mis_ecopuntos(conn, %{"user_id" => user_id}) do

  # ==========================================
  # USER
  # ==========================================
  {:ok, result} =
    Repo.query("""
    SELECT
      id,
      name,
      eco_points
    FROM users
    WHERE id = @1
    """, [user_id])

  if length(result.rows) == 0 do
    json(conn, %{
      success: false,
      message: "Usuario no encontrado"
    })
  else

    row = List.first(result.rows)

    puntos =
      case Enum.at(row, 2) do
        nil -> 0
        value when is_integer(value) -> value
        value when is_float(value) -> round(value)
        value -> String.to_integer(to_string(value))
      end

    # ==========================================
    # NIVEL ACTUAL
    # ==========================================
    {:ok, nivel_result} =
      Repo.query("""
      SELECT TOP 1
        NombreNivel,
        PuntosMinimos,
        PuntosMaximos,
        Color,
        Icono
      FROM NivelesEco
      WHERE @1 BETWEEN PuntosMinimos AND PuntosMaximos
      """, [puntos])

    nivel_actual =
      if length(nivel_result.rows) > 0 do

        nivel_row = List.first(nivel_result.rows)

        %{
          nombre: Enum.at(nivel_row, 0),
          minimo: Enum.at(nivel_row, 1),
          maximo: Enum.at(nivel_row, 2),
          color: Enum.at(nivel_row, 3),
          icono: Enum.at(nivel_row, 4)
        }

      else

        %{
          nombre: "Sin nivel",
          minimo: 0,
          maximo: 0,
          color: "#9E9E9E",
          icono: "eco"
        }

      end

    # ==========================================
    # SIGUIENTE NIVEL
    # ==========================================
    {:ok, siguiente_result} =
      Repo.query("""
      SELECT TOP 1
        NombreNivel,
        PuntosMinimos
      FROM NivelesEco
      WHERE PuntosMinimos > @1
      ORDER BY PuntosMinimos ASC
      """, [puntos])

    siguiente =
      if length(siguiente_result.rows) > 0 do

        next = List.first(siguiente_result.rows)

        %{
          nombre: Enum.at(next, 0),
          puntos: Enum.at(next, 1)
        }

      else

        %{
          nombre: "Nivel máximo",
          puntos: puntos
        }

      end

    # ==========================================
    # RANKING
    # ==========================================
    {:ok, ranking_result} =
      Repo.query("""
      SELECT COUNT(*) + 1
      FROM users
      WHERE eco_points > @1
      """, [puntos])

    ranking =
      ranking_result.rows
      |> List.first()
      |> List.first()

    {:ok, total_result} =
      Repo.query("""
      SELECT COUNT(*)
      FROM users
      WHERE RolId = 2
      """)

    total_users =
      total_result.rows
      |> List.first()
      |> List.first()

   # ==========================================
# HISTORIAL REAL
# ==========================================
{:ok, historial_result} =
  Repo.query("""
  SELECT
    CAST(sr.FechaRegistro AS DATE),
    SUM(srd.Puntos)
  FROM SolicitudReciclajeDetalle srd
  INNER JOIN SolicitudReciclaje sr
    ON sr.Id = srd.SolicitudId
  WHERE sr.UsuarioId = @1
    AND sr.Estado = 'aprobado'
  GROUP BY CAST(sr.FechaRegistro AS DATE)
  ORDER BY CAST(sr.FechaRegistro AS DATE)
  """, [user_id])

historial_real =
  Enum.map(historial_result.rows, fn row ->

    fecha = Enum.at(row, 0)

    semana =
      :calendar.iso_week_number({
        fecha.year,
        fecha.month,
        fecha.day
      })

    puntos_semana =
      case Enum.at(row, 1) do
        nil -> 0
        value when is_integer(value) -> value
        value when is_float(value) -> round(value)
        value -> String.to_integer(to_string(value))
      end

    %{
      semana: "Sem #{elem(semana, 1)}",
      puntos: puntos_semana
    }
  end)

# ==========================================
# GENERAR 4 SEMANAS BASE
# ==========================================
hoy = Date.utc_today()

semanas_base =
  Enum.map(0..3, fn i ->

    fecha =
      Date.add(hoy, -(21 - (i * 7)))

    semana =
      :calendar.iso_week_number({
        fecha.year,
        fecha.month,
        fecha.day
      })

    %{
      semana: "Sem #{elem(semana, 1)}",
      puntos: 0
    }
  end)

# ==========================================
# MERGE
# ==========================================
historial_merge =
  Enum.map(semanas_base, fn base ->

    encontrado =
      Enum.find(historial_real, fn real ->
        real.semana == base.semana
      end)

    if encontrado do
      encontrado
    else
      base
    end
  end)

# ==========================================
# ACUMULATIVO
# ==========================================
{historial_temp, _} =
  Enum.map_reduce(historial_merge, 0, fn item, acc ->

    nuevo_total =
      acc + item.puntos

    {
      %{
        semana: item.semana,
        puntos: nuevo_total
      },
      nuevo_total
    }
  end)

# ==========================================
# ASEGURAR TOTAL REAL
# ==========================================
historial =
  List.update_at(
    historial_temp,
    length(historial_temp) - 1,
    fn item ->
      %{
        semana: item.semana,
        puntos: puntos
      }
    end
  )

    # ==========================================
    # RESPONSE
    # ==========================================
    json(conn, %{
      success: true,

      usuario: %{
        id: Enum.at(row, 0),
        nombre: Enum.at(row, 1)
      },

      total_puntos: puntos,

      nivel_actual: nivel_actual,

      siguiente_nivel: siguiente,

      ranking: ranking,

      total_usuarios: total_users,

      historial: historial
    })

  end
end


def mi_evolucion(conn, params) do

  user_id = Map.get(params, "user_id")

  tipo = Map.get(params, "tipo", "")

  # ==========================================
  # FILTROS
  # ==========================================
  {where_extra, valores} =
    cond do
      tipo != "" ->
        {
          " AND srd.TipoReciclaje = @2",
          [user_id, tipo]
        }

      true ->
        {
          "",
          [user_id]
        }
    end

  # ==========================================
  # ECOPUNTOS POR SEMANA
  # ==========================================
  {:ok, puntos_result} =
    Repo.query("""
    SELECT
      DATEPART(WEEK, sr.FechaRegistro) as Semana,
      SUM(srd.Puntos)
    FROM SolicitudReciclaje sr
    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id
    WHERE sr.UsuarioId = @1
      AND sr.Estado = 'aprobado'
      #{where_extra}
    GROUP BY DATEPART(WEEK, sr.FechaRegistro)
    ORDER BY Semana
    """, valores)

  semanas_raw =
    Enum.map(puntos_result.rows, fn row ->

      puntos =
        case Enum.at(row, 1) do
          nil -> 0
          %Decimal{} = d -> Decimal.to_integer(d)
          value when is_integer(value) -> value
          value when is_float(value) -> round(value)
          value -> String.to_integer(to_string(value))
        end

      %{
        semana: Enum.at(row, 0),
        puntos: puntos
      }
    end)

  # ==========================================
  # GENERAR 4 SEMANAS BASE
  # ==========================================
  today = Date.utc_today()

  semana_actual =
    today
    |> Date.to_erl()
    |> then(fn {year, month, day} ->
      :calendar.iso_week_number({year, month, day})
    end)
    |> elem(1)

  semanas_base =
    Enum.map((semana_actual - 3)..semana_actual, fn sem ->

      encontrado =
        Enum.find(semanas_raw, fn x ->
          x.semana == sem
        end)

      %{
        semana: "Sem #{sem}",
        puntos:
          if encontrado != nil do
            encontrado.puntos
          else
            0
          end
      }
    end)

  # ==========================================
  # ACUMULATIVO
  # ==========================================
  {historial, _acc} =
    Enum.map_reduce(semanas_base, 0, fn item, acc ->

      nuevo = acc + (item.puntos || 0)

      {
        %{
          semana: item.semana,
          puntos: nuevo
        },
        nuevo
      }
    end)

  # ==========================================
  # PUNTOS REALES DEL USUARIO
  # ==========================================
  {:ok, puntos_user_result} =
    Repo.query("""
    SELECT eco_points
    FROM users
    WHERE id = @1
    """, [user_id])

  puntos_actuales =
    case puntos_user_result.rows do
      [[value]] ->
        cond do
          is_nil(value) ->
            0

          match?(%Decimal{}, value) ->
            Decimal.to_integer(value)

          is_integer(value) ->
            value

          is_float(value) ->
            round(value)

          true ->
            String.to_integer(to_string(value))
        end

      _ ->
        0
    end

  # ==========================================
  # ASEGURAR QUE LA ULTIMA SEMANA
  # TENGA LOS ECOPUNTOS REALES
  # ==========================================
  historial =
    if length(historial) > 0 do

      last_index = length(historial) - 1

      Enum.with_index(historial)
      |> Enum.map(fn {item, index} ->

        if index == last_index do
          %{
            semana: item.semana,
            puntos: puntos_actuales
          }
        else
          item
        end
      end)

    else
      historial
    end

  # ==========================================
  # PESO POR MATERIAL
  # ==========================================
  {:ok, peso_result} =
    Repo.query("""
    SELECT
      srd.TipoReciclaje,
      SUM(sr.PesoTotal)
    FROM SolicitudReciclaje sr
    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id
    WHERE sr.UsuarioId = @1
      AND sr.Estado = 'aprobado'
    GROUP BY srd.TipoReciclaje
    """, [user_id])

  peso_materiales_raw =
    Enum.reduce(
      peso_result.rows,
      %{
        "plastico" => 0.0,
        "papel" => 0.0,
        "vidrio" => 0.0,
        "metal" => 0.0
      },
      fn row, acc ->

        tipo =
          row
          |> Enum.at(0)
          |> to_string()
          |> String.downcase()

        peso =
          case Enum.at(row, 1) do
            nil ->
              0.0

            %Decimal{} = d ->
              Decimal.to_float(d)

            value when is_integer(value) ->
              value * 1.0

            value when is_float(value) ->
              value

            value ->
              String.to_float(to_string(value))
          end

        cond do

          String.contains?(tipo, "plastico") or
          String.contains?(tipo, "botella") ->

            Map.update!(
              acc,
              "plastico",
              &(&1 + peso)
            )

          String.contains?(tipo, "papel") ->

            Map.update!(
              acc,
              "papel",
              &(&1 + peso)
            )

          String.contains?(tipo, "vidrio") ->

            Map.update!(
              acc,
              "vidrio",
              &(&1 + peso)
            )

          true ->

            Map.update!(
              acc,
              "metal",
              &(&1 + peso)
            )
        end
      end
    )

  peso_materiales = [
    %{
      material: "plastico",
      peso: Float.round(peso_materiales_raw["plastico"], 2)
    },
    %{
      material: "papel",
      peso: Float.round(peso_materiales_raw["papel"], 2)
    },
    %{
      material: "vidrio",
      peso: Float.round(peso_materiales_raw["vidrio"], 2)
    },
    %{
      material: "metal",
      peso: Float.round(peso_materiales_raw["metal"], 2)
    }
  ]

  # ==========================================
  # VALOR ECONOMICO POR MES
  # ==========================================
  {:ok, valor_result} =
    Repo.query("""
    SELECT
      MONTH(sr.FechaRegistro) as NumeroMes,
      DATENAME(MONTH, sr.FechaRegistro) as Mes,
      SUM(sr.PesoTotal * 1.20)
    FROM SolicitudReciclaje sr
    WHERE sr.UsuarioId = @1
      AND sr.Estado = 'aprobado'
    GROUP BY
      MONTH(sr.FechaRegistro),
      DATENAME(MONTH, sr.FechaRegistro)
    ORDER BY NumeroMes
    """, [user_id])

  valor_mensual_raw =
    Enum.map(valor_result.rows, fn row ->

      valor =
        case Enum.at(row, 2) do
          nil -> 0.0
          %Decimal{} = d -> Decimal.to_float(d)
          value when is_float(value) -> value
          value when is_integer(value) -> value * 1.0
          value -> String.to_float(to_string(value))
        end

      %{
        mes: Enum.at(row, 1),
        valor: Float.round(valor, 2)
      }
    end)

  # ==========================================
  # GENERAR 4 MESES BASE
  # ==========================================
  meses_nombre = %{
    1 => "Jan",
    2 => "Feb",
    3 => "Mar",
    4 => "Apr",
    5 => "May",
    6 => "Jun",
    7 => "Jul",
    8 => "Aug",
    9 => "Sep",
    10 => "Oct",
    11 => "Nov",
    12 => "Dec"
  }

  mes_actual = today.month

  valor_mensual =
    Enum.map((mes_actual - 3)..mes_actual, fn mes ->

      nombre_mes = meses_nombre[mes]

      encontrado =
        Enum.find(valor_mensual_raw, fn x ->
          x.mes == nombre_mes
        end)

      %{
        mes: nombre_mes,
        valor:
          if encontrado != nil do
            encontrado.valor
          else
            0.0
          end
      }
    end)

  # ==========================================
  # RESUMEN COMPARATIVO REAL
  # ==========================================
  penultimo_historial =
    if length(historial) > 1 do
      Enum.at(historial, length(historial) - 2)
    else
      nil
    end

  puntos_pasados =
    if penultimo_historial != nil do
      Map.get(penultimo_historial, :puntos, 0)
    else
      0
    end

  puntos_vs_mes =
    puntos_actuales - puntos_pasados

  peso_total =
    Enum.reduce(peso_materiales, 0.0, fn item, acc ->
      acc + (item.peso || 0.0)
    end)

 # ==========================================
# PESO MES PASADO
# ==========================================
{:ok, peso_mes_pasado_result} =
  Repo.query("""
  SELECT
    SUM(sr.PesoTotal)
  FROM SolicitudReciclaje sr
  WHERE sr.UsuarioId = @1
    AND sr.Estado = 'aprobado'
    AND MONTH(sr.FechaRegistro) = MONTH(GETDATE()) - 1
  """, [user_id])

peso_mes_pasado =
  case peso_mes_pasado_result.rows do
    [[nil]] ->
      0.0

    [[%Decimal{} = d]] ->
      Decimal.to_float(d)

    [[value]] when is_float(value) ->
      value

    [[value]] when is_integer(value) ->
      value * 1.0

    _ ->
      0.0
  end

peso_vs_mes =
  Float.round(
    peso_total - peso_mes_pasado,
    2
  )




  valor_total =
    Enum.reduce(valor_mensual, 0.0, fn item, acc ->
      acc + (item.valor || 0.0)
    end)

# ==========================================
# VALOR MES PASADO
# ==========================================
{:ok, valor_mes_pasado_result} =
  Repo.query("""
  SELECT
    SUM(sr.PesoTotal * 1.20)
  FROM SolicitudReciclaje sr
  WHERE sr.UsuarioId = @1
    AND sr.Estado = 'aprobado'
    AND MONTH(sr.FechaRegistro) = MONTH(GETDATE()) - 1
  """, [user_id])

valor_mes_pasado =
  case valor_mes_pasado_result.rows do

    [[nil]] ->
      0.0

    [[%Decimal{} = d]] ->
      Decimal.to_float(d)

    [[value]] when is_float(value) ->
      value

    [[value]] when is_integer(value) ->
      value * 1.0

    _ ->
      0.0
  end

valor_vs_mes =
  Float.round(
    valor_total - valor_mes_pasado,
    2
  )

  

  # ==========================================
  # RESPONSE
  # ==========================================
  json(conn, %{
    success: true,

    historial: historial,

    peso_materiales: peso_materiales,

    valor_mensual: valor_mensual,

    resumen: %{
      puntos_actuales: puntos_actuales,

      puntos_vs_mes: puntos_vs_mes,

      peso_total: Float.round(peso_total, 2),

      peso_vs_mes: peso_vs_mes,

      valor_total: Float.round(valor_total, 2),

      valor_vs_mes: valor_vs_mes
    }
  })
end

def categorias_reciclaje(conn, _params) do

  {:ok, result} =
    Repo.query("""
    SELECT DISTINCT Categoria
    FROM ConfiguracionReciclaje
    ORDER BY Categoria
    """)

  categorias =
    Enum.map(result.rows, fn row ->
      %{
        categoria: Enum.at(row, 0)
      }
    end)

  json(conn, %{
    success: true,
    categorias: categorias
  })
end

def notificaciones_campanas(conn, params) do

  historial =
    Map.get(params, "historial", "false")

  limite =
    if historial == "true" do
      ""
    else
      "TOP 5"
    end

  {:ok, result} =
    Repo.query("""
    SELECT
      #{limite}

      NombreCampania,
      FechaInicio,
      FechaFin,
      MaterialObjetivo,
      Incentivo,
      FechaRegistro,
      Estado

    FROM Campanias

    ORDER BY FechaRegistro DESC
    """)

  rows =
    Enum.map(result.rows, fn row ->

      %{
        nombre: Enum.at(row, 0),

        fecha_inicio: Enum.at(row, 1),

        fecha_fin: Enum.at(row, 2),

        material: Enum.at(row, 3),

        incentivo: Enum.at(row, 4),

        fecha_registro: Enum.at(row, 5),

        estado: Enum.at(row, 6)
      }

    end)

  json(conn, %{
    success: true,
    campanias: rows
  })

end

end