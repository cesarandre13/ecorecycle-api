defmodule EcorecycleApiWeb.HistorialController do

  use EcorecycleApiWeb, :controller

  alias EcorecycleApi.Repo

  # ====================================
  # GUARDAR RECICLAJE
  # ====================================
  def guardar(conn, params) do

    usuario_id =
      params["usuarioId"]

    tipo_reciclaje =
      params["tipoReciclaje"]

    categoria =
      params["categoria"]

    cantidad =
      params["cantidad"]

    query = """

    INSERT INTO HistorialReciclaje
    (
      UsuarioId,
      TipoReciclaje,
      Categoria,
      Cantidad,
      Estado,
      Puntos,
      Co2Ahorrado
    )

    VALUES
    (
      @1,
      @2,
      @3,
      @4,
      'pendiente',
      0,
      0
    )

    """

    Repo.query!(
      query,
      [
        usuario_id,
        tipo_reciclaje,
        categoria,
        cantidad
      ]
    )

    json(conn, %{
      success: true
    })
  end

  # ====================================
  # LISTAR PENDIENTES
  # ====================================
  def pendientes(conn, _params) do

    query = """

    SELECT
      Id,
      UsuarioId,
      TipoReciclaje,
      Categoria,
      Cantidad,
      Estado,
      FechaRegistro

    FROM HistorialReciclaje

    WHERE Estado = 'pendiente'

    ORDER BY FechaRegistro DESC

    """

    result =
      Repo.query!(query)

    rows =
      Enum.map(result.rows, fn row ->

        %{
          id: Enum.at(row, 0),
          usuarioId: Enum.at(row, 1),
          tipoReciclaje: Enum.at(row, 2),
          categoria: Enum.at(row, 3),
          cantidad: Enum.at(row, 4),
          estado: Enum.at(row, 5),
          fechaRegistro: Enum.at(row, 6)
        }

      end)

    json(conn, rows)
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
    WHERE Id = @p1
    """, [id])

  solicitudRow = List.first(solicitud.rows)

  usuarioId = Enum.at(solicitudRow, 1)

  # =============================
  # OBTENER DETALLES
  # =============================
  {:ok, detalles} =
    Repo.query("""
    SELECT TipoReciclaje, Categoria, Cantidad
    FROM SolicitudReciclajeDetalle
    WHERE SolicitudId = @p1
    """, [id])

  totalPuntos = 0
  totalCo2 = 0

  # =============================
  # CALCULAR
  # =============================
  {puntosFinal, co2Final} =
    Enum.reduce(detalles.rows, {0, 0}, fn row, {accPuntos, accCo2} ->

      tipo = Enum.at(row, 0)
      categoria = Enum.at(row, 1)
      cantidad = Enum.at(row, 2)

      {:ok, config} =
        Repo.query("""
        SELECT PuntosPorUnidad, Co2PorUnidad
        FROM ConfiguracionReciclaje
        WHERE TipoReciclaje = @p1
        """, [tipo])

      if length(config.rows) > 0 do

        configRow = List.first(config.rows)

        puntosUnidad = Enum.at(configRow, 0) || 0
        co2Unidad = Enum.at(configRow, 1) || 0

        puntos = puntosUnidad * cantidad
        co2 = co2Unidad * cantidad

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
    eco_points = eco_points + @p1,
    co2_saved = co2_saved + @p2
  WHERE id = @p3
  """, [
    puntosFinal,
    co2Final,
    usuarioId
  ])

  # =============================
  # ACTUALIZAR SOLICITUD
  # =============================
  Repo.query("""
  UPDATE SolicitudReciclaje
  SET Estado = 'aprobado'
  WHERE Id = @p1
  """, [id])

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
  WHERE Id = @p1
  """, [id])

  json(conn, %{
    success: true
  })
end
end