defmodule EcorecycleApiWeb.AdminController do

  use EcorecycleApiWeb, :controller

  alias EcorecycleApi.Repo
alias Ecto.Adapters.SQL
  # ==========================================
  # OBTENER RECICLAJES PENDIENTES
  # ==========================================
  def pendientes(conn, _params) do

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

        sr.PesoTotal,

        us.UnitManagement

      FROM SolicitudReciclaje sr

      LEFT JOIN SolicitudReciclajeDetalle srd
        ON sr.Id = srd.SolicitudId
      
      LEFT JOIN users us 
        ON us.id = sr.UsuarioId

      WHERE sr.Estado = 'pendiente'


      GROUP BY
        sr.Id,
        sr.Estado,
        sr.FotoUrl,
        sr.FechaRegistro,
        sr.Lote,
        sr.PesoTotal,
         us.UnitManagement

      ORDER BY sr.Id DESC
      """)
      
    

  solicitudes =
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
        unidad: Enum.at(row, 9), 
      }
    end)

  json(conn, %{
    success: true,
    solicitudes: solicitudes
  })
  end

# ====================================
  # APROBAR
  # ====================================
  def aprobar(conn, %{"id" => id}) do

  # =============================
  # OBTENER SOLICITUD
  # =============================
  {:ok, solicitud} =
    Repo.query("""
    SELECT *
    FROM SolicitudReciclaje
    WHERE Id = @1
    """, [id])

  solicitudRow = List.first(solicitud.rows)

  usuarioId = Enum.at(solicitudRow, 1)

  # ==========================================
  # PESO TOTAL
  # ==========================================
  peso_total =
    Enum.at(solicitudRow, 5) || 0

  # =============================
  # OBTENER DETALLES
  # =============================
  {:ok, detalles} =
    Repo.query("""
    SELECT TipoReciclaje, Categoria, Cantidad
    FROM SolicitudReciclajeDetalle
    WHERE SolicitudId = @1
    """, [id])

  # ==========================================
  # OBTENER TIPO MATERIAL
  # ==========================================
  tipo_material =
    detalles.rows
    |> List.first()
    |> Enum.at(0)

  # =============================
  # CALCULAR PUNTOS + CO2
  # =============================
  {puntosFinal, co2Final} =
    Enum.reduce(detalles.rows, {0, 0}, fn row, {accPuntos, accCo2} ->

      tipo = Enum.at(row, 0)

      cantidad = Enum.at(row, 2)

      {:ok, config} =
        Repo.query("""
        SELECT PuntosPorUnidad, Co2PorUnidad
        FROM ConfiguracionReciclaje
        WHERE TipoReciclaje = @1
        """, [tipo])

      if length(config.rows) > 0 do

        configRow = List.first(config.rows)

        puntosUnidad =
          Enum.at(configRow, 0) || 0

        co2Unidad =
          Enum.at(configRow, 1) || 0

        puntos =
          puntosUnidad * cantidad

        co2 =
          co2Unidad * cantidad

        {
          accPuntos + puntos,
          accCo2 + co2
        }

      else

        {
          accPuntos,
          accCo2
        }

      end
    end)

  # =============================
  # ACTUALIZAR USER
  # =============================
  Repo.query("""
  UPDATE users
  SET
    eco_points = ISNULL(eco_points, 0) + @1,
    co2_saved = ISNULL(co2_saved, 0) + @2
  WHERE id = @3
  """, [
    puntosFinal,
    co2Final,
    usuarioId
  ])

  # =============================
  # APROBAR SOLICITUD
  # =============================
  Repo.query("""
  UPDATE SolicitudReciclaje
  SET Estado = 'aprobado'
  WHERE Id = @1
  """, [id])

  # ==========================================
  # ACTUALIZAR CONTENEDOR
  # ==========================================
  Repo.query("""
  UPDATE ContenedorReciclaje
  SET PesoActual = ISNULL(PesoActual, 0) + @1
  WHERE Id = 1
  """, [
    peso_total
  ])

  # ==========================================
  # VALIDAR CAPACIDAD
  # ==========================================
  Repo.query("""
  UPDATE ContenedorReciclaje
  SET Estado =
    CASE
      WHEN PesoActual >= CapacidadMaxima
      THEN 'lleno'
      ELSE 'activo'
    END
  WHERE Id = 1
  """, [
    tipo_material
  ])

  json(conn, %{
    success: true,
    puntos: puntosFinal,
    co2: co2Final
  })

end

  # ====================================
  # RECHAZAR
  # ====================================
  def rechazar(conn, %{"id" => id}) do

  Repo.query("""
  UPDATE SolicitudReciclaje
  SET Estado = 'rechazado'
  WHERE Id = @1
  """, [id])

  json(conn, %{
    success: true
  })
end

def contenedores(conn, _params) do

  {:ok, result} =
    SQL.query(
      Repo,
      """
      SELECT
        Id,
        TipoMaterial,
        ISNULL(PesoActual,0),
        ISNULL(CapacidadMaxima,0),
        Estado,
        (
          PesoActual * 100.0 / CapacidadMaxima
        ) AS Porcentaje
      FROM ContenedorReciclaje
      """,
      []
    )

  json(conn, %{
    success: true,
    contenedores:
      Enum.map(result.rows, fn row ->

        %{
          id: Enum.at(row, 0),
          tipo: Enum.at(row, 1),
          peso_actual:  row
          |> Enum.at(2)
          |> Decimal.to_float(),

        capacidad:
          row
          |> Enum.at(3)
          |> Decimal.to_float(),
          estado: Enum.at(row, 4),
          porcentaje: Enum.at(row, 5)
        }

      end)
  })

end

def recojo(conn, params) do

  contenedor_id = params["contenedor_id"]

  transportista_id = params["transportista_id"]

  horario = params["horario"]

  fecharecojo = params["fecha_recojo"]

  valoreconomico = params["valor_economico"]

  pesototal = params["peso_total"]

  # ==========================================
  # GENERAR CODIGO
  # ==========================================
  fecha =
    Date.utc_today()
    |> Date.to_string()
    |> String.replace("-", "")

  {:ok, result} =
    SQL.query(
      Repo,
      """
      SELECT COUNT(*)
      FROM SolicitudRecojo
      WHERE CONVERT(date, FechaRegistro)
      =
      CONVERT(date, GETDATE())
      """,
      []
    )

  count =
    result.rows
    |> List.first()
    |> List.first()

  correlativo =
    (count + 1)
    |> Integer.to_string()
    |> String.pad_leading(3, "0")

  codigo = "RECOJO-#{fecha}-#{correlativo}"

  # ==========================================
  # INSERTAR
  # ==========================================
  SQL.query(
    Repo,
    """
    INSERT INTO SolicitudRecojo
    (
      Codigo,
      ContenedorId,
      Transportista,
      Horario,
      FechaRecojo,
      Estado,
      ValorEconomico,
      PesoTotal
    )
    VALUES
    (
      @1,
      @2,
      @3,
      @4,
      @5,
      'pendiente',
      @6,
      @7
    )
    """,
    [
      codigo,
      contenedor_id,
      transportista_id,
      horario,
      fecharecojo,
      valoreconomico,
      pesototal
    ]
  )

  # ==========================================
  # ACTUALIZAR CAPACIDAD A 0
  # ==========================================
  Repo.query("""
  UPDATE ContenedorReciclaje
  SET 
    Estado = 'activo',
    PesoActual = 0.00
  WHERE Id = 1
  """
  )

  json(conn, %{
    success: true,
    codigo: codigo
  })

end

  def transportistas(conn, _params) do

    result =
      SQL.query!(
        Repo,
        """
        SELECT
          IdTransporter,
          CompanyName
        FROM Transporter
        """,
      []
    )

    json(conn, %{
    success: true,
    transportistas:
      Enum.map(result.rows, fn row ->

        %{
          IdTransportista: Enum.at(row, 0),
          NombreTransportista: Enum.at(row, 1)
        }

      end)
  })
  end

 def seguimiento_entregas(conn, params) do

  estado = Map.get(params, "estado", "")
  tipo = Map.get(params, "tipo", "")
  unidad = Map.get(params, "unidad", "")
  fecha = Map.get(params, "fecha", "")

  query = """
  SELECT
    sr.Id,
    sr.Lote,
    u.name,
    srd.TipoReciclaje,
    srd.Cantidad,
    sr.PesoTotal,
    srd.Puntos,
    sr.Estado,
    sr.FechaRegistro,
    srd.Co2Ahorrado,
    u.UnitManagement as Unidad
  FROM SolicitudReciclaje sr
  INNER JOIN users u
    ON u.id = sr.UsuarioId
  INNER JOIN SolicitudReciclajeDetalle srd
    ON srd.SolicitudId = sr.Id
  WHERE 1=1
  """

  # ==========================================
  # FILTRO ESTADO
  # ==========================================
  {query, params_query} =
    cond do

      estado != "" and estado != "todos" ->
        {
          query <> " AND sr.Estado = @1",
          [estado]
        }

      true ->
        {
          query,
          []
        }
    end

  {:ok, result} =
    Repo.query(query, params_query)

  # ==========================================
  # MAPEAR ENTREGAS
  # ==========================================
  entregas =
    Enum.map(result.rows, fn row ->

      peso =
        case Enum.at(row, 5) do
          nil -> Decimal.new("0")
          %Decimal{} = val -> val
          val when is_float(val) -> Decimal.from_float(val)
          val when is_integer(val) -> Decimal.new(val)
          val -> Decimal.new(to_string(val))
        end

      puntos =
        case Enum.at(row, 6) do
          nil -> Decimal.new("0")
          %Decimal{} = val -> val
          val when is_float(val) -> Decimal.from_float(val)
          val when is_integer(val) -> Decimal.new(val)
          val -> Decimal.new(to_string(val))
        end

      valor_economico =
        Decimal.mult(
          peso,
          Decimal.new("1.20")
        )

      %{
        id: Enum.at(row, 0),
        lote: Enum.at(row, 1),
        usuario: Enum.at(row, 2),
        tipo_reciclaje: Enum.at(row, 3),
        cantidad: Enum.at(row, 4),
        peso: Decimal.to_string(peso),
        puntos: Decimal.to_string(puntos),
        estado: Enum.at(row, 7),
        fecha: Enum.at(row, 8),
        co2: Enum.at(row, 9),
        unidad: Enum.at(row, 10),
        valor_economico:
          Decimal.to_string(valor_economico)
      }
    end)

  # ==========================================
  # RESUMEN
  # ==========================================
  pendientes =
    Enum.count(entregas, fn x ->
      x.estado == "pendiente"
    end)

  aprobadas =
    Enum.count(entregas, fn x ->
      x.estado == "aprobado"
    end)

  rechazadas =
    Enum.count(entregas, fn x ->
      x.estado == "rechazado"
    end)

  # ==========================================
  # PESO TOTAL
  # ==========================================
  peso_total =
    Enum.reduce(result.rows, Decimal.new("0"), fn row, acc ->

      peso =
        case Enum.at(row, 5) do
          nil -> Decimal.new("0")
          %Decimal{} = val -> val
          val when is_float(val) -> Decimal.from_float(val)
          val when is_integer(val) -> Decimal.new(val)
          val -> Decimal.new(to_string(val))
        end

      Decimal.add(acc, peso)
    end)

  # ==========================================
  # PUNTOS ACREDITADOS
  # ==========================================
  puntos_acreditados =
    Enum.reduce(result.rows, Decimal.new("0"), fn row, acc ->

      estado_row = Enum.at(row, 7)

      puntos =
        case Enum.at(row, 6) do
          nil -> Decimal.new("0")
          %Decimal{} = val -> val
          val when is_float(val) -> Decimal.from_float(val)
          val when is_integer(val) -> Decimal.new(val)
          val -> Decimal.new(to_string(val))
        end

      if estado_row == "aprobado" do
        Decimal.add(acc, puntos)
      else
        acc
      end
    end)

  json(conn, %{
    success: true,
    entregas: entregas,
    resumen: %{
      pendientes: pendientes,
      aprobadas: aprobadas,
      rechazadas: rechazadas,
      peso_total: Decimal.to_string(peso_total),
      puntos_acreditados: Decimal.to_string(puntos_acreditados)
    }
  })
end

def historial_participacion(conn, params) do

  search = Map.get(params, "search", "")

  query = """
  SELECT
    sr.Id,
    sr.Lote,
    sr.FechaRegistro,
    srd.TipoReciclaje,
    srd.Cantidad,
    sr.PesoTotal,
    srd.Puntos,
    sr.Estado,
    u.id,
    u.name,
    u.UnitManagement
  FROM SolicitudReciclaje sr
  INNER JOIN users u
    ON u.id = sr.UsuarioId
  INNER JOIN SolicitudReciclajeDetalle srd
    ON srd.SolicitudId = sr.Id
  WHERE
    u.name LIKE @1
    OR CAST(u.id AS VARCHAR) LIKE @1
    OR u.UnitManagement LIKE @1
  ORDER BY sr.FechaRegistro DESC
  """

  {:ok, result} =
    Repo.query(query, ["%#{search}%"])

  solicitudes =
    Enum.map(result.rows, fn row ->

      peso =
        case Enum.at(row, 5) do
          nil -> 0.0
          value when is_float(value) -> value
          value -> Decimal.to_float(value)
        end

      puntos =
        case Enum.at(row, 6) do
          nil -> 0
          value when is_integer(value) -> value
          value when is_float(value) -> round(value)
          value -> String.to_integer(Decimal.to_string(value))
        end

      %{
        id_solicitud: Enum.at(row, 0),
        lote: Enum.at(row, 1),
        fecha: Enum.at(row, 2),
        tipo_reciclaje: Enum.at(row, 3),
        cantidad: Enum.at(row, 4),
        peso: peso,
        puntos: puntos,
        estado: Enum.at(row, 7),
        usuario_id: Enum.at(row, 8),
        usuario: Enum.at(row, 9),
        unidad: Enum.at(row, 10),
        valor_economico: Float.round(peso * 1.20, 2)
      }
    end)

  total_solicitudes =
    Enum.count(solicitudes)

  peso_total =
    Enum.reduce(solicitudes, 0.0, fn item, acc ->
      acc + item.peso
    end)

  valor_total =
    Enum.reduce(solicitudes, 0.0, fn item, acc ->
      acc + item.valor_economico
    end)

  puntos_aprobados =
    Enum.reduce(solicitudes, 0, fn item, acc ->

      if item.estado == "aprobado" do
        acc + item.puntos
      else
        acc
      end
    end)

  json(conn, %{
    success: true,
    solicitudes: solicitudes,
    resumen: %{
      total_solicitudes: total_solicitudes,
      peso_total: Float.round(peso_total, 2),
      valor_total: Float.round(valor_total, 2),
      puntos_aprobados: puntos_aprobados,
      beneficios_canjeados: 0,
      nivel_colaborador: ""
    }
  })
end

def reporte_consolidado(conn, params) do

  fecha_inicio =
    Map.get(
      params,
      "fecha_inicio",
      "2024-01-01"
    )

  fecha_fin =
    Map.get(
      params,
      "fecha_fin",
      Date.utc_today() |> to_string()
    )

  {:ok, result} =
    Repo.query("""
    SELECT
      srd.Categoria,

      COUNT(DISTINCT sr.Id) as entregas,

      SUM(sr.PesoTotal) as peso,

      SUM(srd.Puntos) as puntos,

      SUM(sr.PesoTotal * 1.20) as valor

    FROM SolicitudReciclaje sr

    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id

    WHERE sr.Estado = 'aprobado'

      AND CAST(sr.FechaRegistro AS DATE)
        BETWEEN @1 AND @2

    GROUP BY srd.Categoria

    ORDER BY srd.Categoria
    """, [
      fecha_inicio,
      fecha_fin
    ])

  materiales =
    Enum.map(result.rows, fn row ->

      peso =
        case Enum.at(row, 2) do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_float(n) -> n
          n when is_integer(n) -> n * 1.0
          _ -> 0.0
        end

      valor =
        case Enum.at(row, 4) do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_float(n) -> n
          n when is_integer(n) -> n * 1.0
          _ -> 0.0
        end

      %{
        material: Enum.at(row, 0),
        entregas: Enum.at(row, 1) || 0,
        peso: Float.round(peso, 2),
        puntos: Enum.at(row, 3) || 0,
        valor: Float.round(valor, 2)
      }
    end)

  resumen = %{
    peso_total:
      Enum.reduce(materiales, 0.0, fn x, acc ->
        acc + x.peso
      end),

    valor_total:
      Enum.reduce(materiales, 0.0, fn x, acc ->
        acc + x.valor
      end),

    puntos_total:
      Enum.reduce(materiales, 0, fn x, acc ->
        acc + x.puntos
      end),

    entregas_total:
      Enum.reduce(materiales, 0, fn x, acc ->
        acc + x.entregas
      end)
  }

  json(conn, %{
    success: true,
    materiales: materiales,
    resumen: resumen
  })
end

def reporte_bloques(conn, params) do

  fecha_inicio =
    Map.get(
      params,
      "fecha_inicio",
      "2024-01-01"
    )

  fecha_fin =
    Map.get(
      params,
      "fecha_fin",
      Date.utc_today() |> to_string()
    )

  {:ok, result} =
    Repo.query("""

    SELECT

      bm.Name,

      COUNT(DISTINCT u.id) as vecinos,

      COUNT(DISTINCT sr.Id) as entregas,

      SUM(sr.PesoTotal) as peso,

      SUM(sr.PesoTotal * 1.20) as valor,

      SUM(srd.Puntos) as puntos

    FROM BlockManagement bm

    INNER JOIN UnitManagement um
      ON um.IdBlockManager = bm.IdBlockManager

    INNER JOIN users u
      ON u.UnitManagement = um.IdUnitManagement

    LEFT JOIN SolicitudReciclaje sr
      ON sr.UsuarioId = u.id
      AND sr.Estado = 'aprobado'

    LEFT JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id

    WHERE
      sr.FechaRegistro IS NULL
      OR CAST(sr.FechaRegistro AS DATE)
      BETWEEN @1 AND @2

    GROUP BY bm.Name

    ORDER BY bm.Name

    """, [
      fecha_inicio,
      fecha_fin
    ])

  bloques =
    Enum.map(result.rows, fn row ->

      peso =
        case Enum.at(row, 3) do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_float(n) -> n
          n when is_integer(n) -> n * 1.0
          _ -> 0.0
        end

      valor =
        case Enum.at(row, 4) do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_float(n) -> n
          n when is_integer(n) -> n * 1.0
          _ -> 0.0
        end

      puntos =
        case Enum.at(row, 5) do
          nil -> 0
          n when is_integer(n) -> n
          n when is_float(n) -> round(n)
          _ -> 0
        end

      vecinos =
        Enum.at(row, 1) || 0

      promedio =
        if vecinos > 0 do
          puntos / vecinos
        else
          0
        end

      nivel =
        cond do
          promedio >= 500 -> "Diamante"
          promedio >= 300 -> "Oro"
          promedio >= 150 -> "Plata"
          promedio >= 50 -> "Bronce"
          true -> "Inicial"
        end

      %{
        bloque: Enum.at(row, 0),

        vecinos: vecinos,

        entregas:
          Enum.at(row, 2) || 0,

        peso:
          Float.round(peso, 2),

        valor:
          Float.round(valor, 2),

        puntos: puntos,

        nivel: nivel
      }
    end)

  resumen = %{

    vecinos_participantes:
      Enum.reduce(bloques, 0, fn x, acc ->
        acc + x.vecinos
      end),

    entregas_totales:
      Enum.reduce(bloques, 0, fn x, acc ->
        acc + x.entregas
      end),

    peso_total:
      Enum.reduce(bloques, 0.0, fn x, acc ->
        acc + x.peso
      end),

    valor_total:
      Enum.reduce(bloques, 0.0, fn x, acc ->
        acc + x.valor
      end),

    puntos_totales:
      Enum.reduce(bloques, 0, fn x, acc ->
        acc + x.puntos
      end)
  }

  json(conn, %{
    success: true,
    bloques: bloques,
    resumen: resumen
  })
end

def evolucion_material(conn, params) do

  fecha_inicio =
    Map.get(params, "fecha_inicio", "")

  fecha_fin =
    Map.get(params, "fecha_fin", "")

  {filtro_fecha, valores} =
    cond do

      fecha_inicio != "" and fecha_fin != "" ->

        {
          """
          AND CAST(sr.FechaRegistro AS DATE)
          BETWEEN @1 AND @2
          """,
          [fecha_inicio, fecha_fin]
        }

      true ->
        {"", []}
    end

  # ==========================================
  # PESO POR MATERIAL
  # ==========================================

  {:ok, peso_result} =
    Repo.query("""
    SELECT
      cr.Categoria,
      SUM(sr.PesoTotal)
    FROM SolicitudReciclaje sr

    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id

    INNER JOIN ConfiguracionReciclaje cr
      ON cr.TipoReciclaje = srd.TipoReciclaje

    WHERE sr.Estado = 'aprobado'
    #{filtro_fecha}

    GROUP BY cr.Categoria
    """, valores)

  peso_material =
    Enum.map(peso_result.rows, fn row ->

      peso =
        case Enum.at(row, 1) do
          nil -> 0.0
          %Decimal{} = d -> Decimal.to_float(d)
          value when is_float(value) -> value
          value when is_integer(value) -> value * 1.0
          _ -> 0.0
        end

      %{
        material: to_string(Enum.at(row, 0)),
        peso: Float.round(peso, 2)
      }
    end)

  # ==========================================
  # ECOPUNTOS POR MATERIAL
  # ==========================================

  {:ok, puntos_result} =
    Repo.query("""
    SELECT
      cr.Categoria,
      SUM(srd.Puntos)

    FROM SolicitudReciclaje sr

    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id

    INNER JOIN ConfiguracionReciclaje cr
      ON cr.TipoReciclaje = srd.TipoReciclaje

    WHERE sr.Estado = 'aprobado'
    #{filtro_fecha}

    GROUP BY cr.Categoria
    """, valores)

  puntos_material =
    Enum.map(puntos_result.rows, fn row ->

      puntos =
        case Enum.at(row, 1) do
          nil -> 0
          value when is_integer(value) -> value
          value when is_float(value) -> round(value)
          _ -> 0
        end

      %{
        material: to_string(Enum.at(row, 0)),
        puntos: puntos
      }
    end)

  # ==========================================
  # VALOR ECONOMICO
  # ==========================================

  {:ok, valor_result} =
    Repo.query("""
    SELECT
      cr.Categoria,
      SUM(sr.PesoTotal * 1.20)

    FROM SolicitudReciclaje sr

    INNER JOIN SolicitudReciclajeDetalle srd
      ON srd.SolicitudId = sr.Id

    INNER JOIN ConfiguracionReciclaje cr
      ON cr.TipoReciclaje = srd.TipoReciclaje

    WHERE sr.Estado = 'aprobado'
    #{filtro_fecha}

    GROUP BY cr.Categoria
    """, valores)

  valor_material =
    Enum.map(valor_result.rows, fn row ->

      valor =
        case Enum.at(row, 1) do
          nil -> 0.0
          %Decimal{} = d -> Decimal.to_float(d)
          value when is_float(value) -> value
          value when is_integer(value) -> value * 1.0
          _ -> 0.0
        end

      %{
        material: to_string(Enum.at(row, 0)),
        valor: Float.round(valor, 2)
      }
    end)

  # ==========================================
  # RESUMEN
  # ==========================================

  material_mas_reciclado =
    peso_material
    |> Enum.sort_by(& &1.peso, :desc)
    |> List.first()

  material_mas_puntos =
    puntos_material
    |> Enum.sort_by(& &1.puntos, :desc)
    |> List.first()

  material_mas_valor =
    valor_material
    |> Enum.sort_by(& &1.valor, :desc)
    |> List.first()

  

  json(conn, %{
    success: true,

    peso_material: peso_material,

    puntos_material: puntos_material,

    valor_material: valor_material,

    resumen: %{

      material_mas_reciclado:
        if material_mas_reciclado != nil do
          material_mas_reciclado.material
        else
          "-"
        end,

      material_mas_puntos:
        if material_mas_puntos != nil do
          material_mas_puntos.material
        else
          "-"
        end,

      material_mas_valor:
        if material_mas_valor != nil do
          material_mas_valor.material
        else
          "-"
        end
    }
  })
end

def entregas_transportador(conn, params) do

  transportador =
    Map.get(params, "transportador", "")

  estado =
    Map.get(params, "estado", "")

  fecha_inicio =
    Map.get(params, "fecha_inicio", "")

  fecha_fin =
    Map.get(params, "fecha_fin", "")

  # ==========================================
  # FILTROS
  # ==========================================

  filtros = []
  valores = []

  {filtros, valores} =
    if transportador != "" do
      {
        filtros ++ [" AND U.name = @#{length(valores) + 1}"],
        valores ++ [transportador]
      }
    else
      {filtros, valores}
    end

  {filtros, valores} =
    if estado != "" do
      {
        filtros ++ [" AND SR.Estado = @#{length(valores) + 1}"],
        valores ++ [estado]
      }
    else
      {filtros, valores}
    end

  {filtros, valores} =
    if fecha_inicio != "" do
      {
        filtros ++ [" AND CAST(SR.FechaRegistro AS DATE) >= @#{length(valores) + 1}"],
        valores ++ [fecha_inicio]
      }
    else
      {filtros, valores}
    end

  {filtros, valores} =
    if fecha_fin != "" do
      {
        filtros ++ [" AND CAST(SR.FechaRegistro AS DATE) <= @#{length(valores) + 1}"],
        valores ++ [fecha_fin]
      }
    else
      {filtros, valores}
    end

  where_extra =
    Enum.join(filtros, "")

  # ==========================================
  # CONSULTA
  # ==========================================

  {:ok, result} =
    Repo.query("""
     SELECT
	  DISTINCT

      U.CompanyName,
      SR.Codigo,
      CR.Categoria,
      SR.PesoTotal,
      SR.ValorEconomico,
      SR.FechaRegistro,
      SR.Estado

    FROM SolicitudRecojo SR

    INNER JOIN Transporter U
    ON U.IdTransporter= SR.Transportista

    INNER JOIN ConfiguracionReciclaje CR
    ON CR.Categoria = 'plastico'

    WHERE U.IdTransporter IS NOT NULL
    #{where_extra}

    ORDER BY
      U.CompanyName,
      SR.FechaRegistro DESC
    """, valores)

  IO.inspect(result.rows, label: "RESULT ROWS")

  rows =
    Enum.map(result.rows, fn row ->

      peso =
        case Enum.at(row, 3) do
          %Decimal{} = d -> Decimal.to_float(d)
          v when is_float(v) -> v
          v when is_integer(v) -> v * 1.0
          _ -> 0.0
        end

      valor =
        case Enum.at(row, 4) do
          %Decimal{} = d -> Decimal.to_float(d)
          v when is_float(v) -> v
          v when is_integer(v) -> v * 1.0
          _ -> 0.0
        end

      %{
        transportador: Enum.at(row, 0),
        codigo: Enum.at(row, 1),
        material: Enum.at(row, 2),
        peso: Float.round(peso, 2),
        valor: Float.round(valor, 2),
        fecha: Enum.at(row, 5),
        estado: Enum.at(row, 6)
      }
    end)

  IO.inspect(rows, label: "ROWS MAP")
# ==========================================
# RESUMEN
# ==========================================

rows_aprobados =
  Enum.filter(rows, fn x ->

    estado =
      x[:estado]
      |> to_string()
      |> String.trim()
      |> String.downcase()

    estado == "aprobado"
  end)

pendientes =
  Enum.count(rows, fn x ->

    estado =
      x[:estado]
      |> to_string()
      |> String.trim()
      |> String.downcase()

    estado == "pendiente"
  end)

aprobadas =
  length(rows_aprobados)

rechazadas =
  Enum.count(rows, fn x ->

    estado =
      x[:estado]
      |> to_string()
      |> String.trim()
      |> String.downcase()

    estado == "rechazado"
  end)

peso_total =
  Enum.reduce(rows_aprobados, 0.0, fn x, acc ->

    peso =
      case x[:peso] do
        nil -> 0.0
        v when is_float(v) -> v
        v when is_integer(v) -> v * 1.0
        _ -> 0.0
      end

    acc + peso
  end)

valor_total =
  Enum.reduce(rows_aprobados, 0.0, fn x, acc ->

    valor =
      case x[:valor] do
        nil -> 0.0
        v when is_float(v) -> v
        v when is_integer(v) -> v * 1.0
        _ -> 0.0
      end

    acc + valor
  end)

  json(conn, %{
    success: true,

    entregas: rows,

    resumen: %{
      pendientes: pendientes,
      recolectadas: aprobadas,
      rechazadas: rechazadas,
      peso_total: Float.round(peso_total, 2),
      valor_total: Float.round(valor_total, 2)
    }
  })
end
end