defmodule EcorecycleApiWeb.RecyclingController do

  use EcorecycleApiWeb, :controller

  alias EcorecycleApi.Repo
  alias Ecto.Adapters.SQL

  # ==========================================
  # GUARDAR SOLICITUD
  # ==========================================
  def save(conn, params) do

    usuario_id = params["usuario_id"]

    detalles =
      Jason.decode!(params["detalles"])

    # ==========================================
    # GUARDAR FOTO
    # ==========================================
    upload = params["foto"]

    filename =
      "#{System.system_time(:millisecond)}_#{upload.filename}"

    upload_path =
      Path.join([
        "priv/static/uploads",
        filename
      ])

    File.cp!(upload.path, upload_path)

    foto_url =
      "/uploads/#{filename}"

    # ==========================================
    # CREAR SOLICITUD
    # ==========================================
    {:ok, result} =
      SQL.query(
        Repo,
        """
        INSERT INTO SolicitudReciclaje
        (
          UsuarioId,
          Estado,
          FotoUrl
        )

        OUTPUT INSERTED.Id

        VALUES
        (
          @1,
          'pendiente',
          @2
        )
        """,
        [
          usuario_id,
          foto_url
        ]
      )

    [[solicitud_id]] = result.rows

    # ==========================================
    # GENERAR LOTE
    # ==========================================
    lote =
      "LOTE-" <>
      String.pad_leading("#{solicitud_id}", 6, "0")

    SQL.query!(
      Repo,
      """
      UPDATE SolicitudReciclaje
      SET Lote = @1
      WHERE Id = @2
      """,
      [
        lote,
        solicitud_id
      ]
    )

    # ==========================================
    # TOTALES
    # ==========================================
    peso_total =
      Decimal.new("0")

    valor_total =
      Decimal.new("0")

    # ==========================================
    # GUARDAR DETALLES
    # ==========================================
    Enum.each(detalles, fn item ->

      tipo =
        item["tipo_reciclaje"]

      categoria =
        item["categoria"]

      cantidad =
        item["cantidad"]

      # ==========================================
      # CONFIG RECICLAJE
      # ==========================================
      {:ok, peso_result} =
        SQL.query(
          Repo,
          """
          SELECT
            PesoUnidad,
            PuntosPorUnidad,
            Alias
          FROM ConfiguracionReciclaje
          WHERE TipoReciclaje = @1
          """,
          [tipo]
        )

      {peso_unidad, puntos, alias_name} =
        case peso_result.rows do
          [[peso, puntos, alias_name]] ->
            {peso, puntos, alias_name}

          _ ->
            {
              Decimal.new("0"),
              0,
              tipo
            }
        end

      # ==========================================
      # PESO ITEM
      # ==========================================
      peso =
        Decimal.mult(
          Decimal.new(cantidad),
          peso_unidad
        )

      # ==========================================
      # CO2
      # ==========================================
      {:ok, co2_result} =
        SQL.query(
          Repo,
          """
          SELECT
            Co2PorUnidad
          FROM ConfiguracionReciclaje
          WHERE TipoReciclaje = @1
          """,
          [tipo]
        )

      co2_unidad =
        case co2_result.rows do
          [[valor]] -> valor
          _ -> Decimal.new("0")
        end

      co2 =
        Decimal.mult(
          Decimal.new(cantidad),
          Decimal.from_float(co2_unidad)
        )

      # ==========================================
      # VALOR POR KILO
      # ==========================================
      {:ok, precio_result} =
        SQL.query(
          Repo,
          """
          SELECT
            PrecioPorKilo
          FROM ConfiguracionValorReciclaje
          WHERE Categoria = @1
          """,
          [categoria]
        )

      precio =
        case precio_result.rows do
          [[valor]] ->
            valor

          _ ->
            Decimal.new("0")
        end

      # ==========================================
      # VALOR ITEM
      # ==========================================
      valor_item =
        Decimal.mult(
          peso,
          precio
        )

      # ==========================================
      # ACUMULAR TOTALES
      # ==========================================
      peso_total =
        Decimal.add(
          peso_total,
          peso
        )

      valor_total =
        Decimal.add(
          valor_total,
          valor_item
        )

      # ==========================================
      # INSERT DETALLE
      # ==========================================
      SQL.query!(
        Repo,
        """
        INSERT INTO SolicitudReciclajeDetalle
        (
          SolicitudId,
          TipoReciclaje,
          Categoria,
          Cantidad,
          Peso,
          Puntos,
          Co2Ahorrado
        )

        VALUES
        (
          @1,
          @2,
          @3,
          @4,
          @5,
          @6,
          @7
        )
        """,
        [
          solicitud_id,
          tipo,
          categoria,
          cantidad,
          peso,
          puntos,
          co2
        ]
      )

    end)

    # ==========================================
    # RECALCULAR TOTALES
    # ==========================================
    {:ok, total_result} =
      SQL.query(
        Repo,
        """
        SELECT
          SUM(Peso),
          SUM(Puntos)
        FROM SolicitudReciclajeDetalle
        WHERE SolicitudId = @1
        """,
        [solicitud_id]
      )

    [[peso_total_db, puntos_total]] =
      total_result.rows

    peso_total_db =
      peso_total_db || Decimal.new("0")

    puntos_total =
      puntos_total || 0

    # ==========================================
    # VALOR TOTAL FINAL
    # ==========================================
    valor_total_final =
      Decimal.mult(
        peso_total_db,
        Decimal.new("1.10")
      )

    # ==========================================
    # UPDATE SOLICITUD
    # ==========================================
    SQL.query!(
      Repo,
      """
      UPDATE SolicitudReciclaje
      SET
        PesoTotal = @1,
        ValorTotal = @2
      WHERE Id = @3
      """,
      [
        peso_total_db,
        valor_total_final,
        solicitud_id
      ]
    )

    json(conn, %{
      success: true,
      solicitud_id: solicitud_id,
      lote: lote,
      peso_total: Decimal.to_string(peso_total_db),
      valor_total: Decimal.to_string(valor_total_final),
      puntos_total: puntos_total,
      foto_url: foto_url
    })

  end

  # ==========================================
  # PERFIL
  # ==========================================
  def perfil(conn, %{"id" => id}) do

  result =
    SQL.query!(
      Repo,
      """
      SELECT
        U.name,
        U.email,
        U.eco_points,
        U.co2_saved,
        U.UnitManagement,
        NE.NombreNivel,
        NE.Id

      FROM users U

      LEFT JOIN NivelesEco NE
        ON U.eco_points BETWEEN NE.PuntosMinimos
        AND NE.PuntosMaximos

      WHERE U.id = @1
      """,
      [id]
    )

  row =
    List.first(result.rows)

  if row == nil do

    json(conn, %{
      success: false
    })

  else

    json(conn, %{
      success: true,

      usuario: %{
        nombre: Enum.at(row, 0),
        email: Enum.at(row, 1),
        puntos: Enum.at(row, 2),
        co2: Enum.at(row, 3),
        unidad: Enum.at(row, 4),
        

        level:
          Enum.at(row, 5) || "Semilla",
          idlevel: Enum.at(row, 6)
      }
    })

  end
end

  # ==========================================
  # DETALLE SOLICITUD
  # ==========================================
  def detalle_solicitud(conn, %{"id" => id}) do

    # ==========================================
    # SOLICITUD
    # ==========================================
    {:ok, solicitud} =
      SQL.query(
        Repo,
        """
        SELECT
  s.Id,
  s.Estado,
  s.FotoUrl,
  s.FechaRegistro,
  s.PesoTotal,
  s.ValorTotal,
  s.Lote,

  ISNULL(SUM(d.Puntos), 0) as PuntosTotales,
  ISNULL(SUM(d.Co2Ahorrado), 0) as Co2Total

FROM SolicitudReciclaje s

LEFT JOIN SolicitudReciclajeDetalle d
  ON d.SolicitudId = s.Id

WHERE s.Id = @1

GROUP BY
  s.Id,
  s.Estado,
  s.FotoUrl,
  s.FechaRegistro,
  s.PesoTotal,
  s.ValorTotal,
  s.Lote
        """,
        [id]
      )

  # ==========================================
# DETALLES
# ==========================================
{:ok, detalles} =
  SQL.query(
    Repo,
    """
    SELECT
      d.TipoReciclaje,
      d.Categoria,
      d.Cantidad,
      d.Peso,
      d.Puntos,
      d.Co2Ahorrado,
      c.Alias

    FROM SolicitudReciclajeDetalle d

    LEFT JOIN ConfiguracionReciclaje c
      ON c.TipoReciclaje = d.TipoReciclaje

    WHERE d.SolicitudId = @1
    """,
    [id]
  )

    [solicitud_row] =
      solicitud.rows

    json(conn, %{
      success: true,

      solicitud: %{
        id: Enum.at(solicitud_row, 0),
        estado: Enum.at(solicitud_row, 1),
        foto_url: Enum.at(solicitud_row, 2),
        fecha: Enum.at(solicitud_row, 3),
        peso_total: Enum.at(solicitud_row, 4),
        valor_total: Enum.at(solicitud_row, 5),
        lote: Enum.at(solicitud_row, 6),
        puntos: Enum.at(solicitud_row, 7),
        co2_total: Enum.at(solicitud_row, 8)
      },

      detalles:
        Enum.map(detalles.rows, fn row ->

          %{
            tipo_reciclaje: Enum.at(row, 0),
            categoria: Enum.at(row, 1),
            cantidad: Enum.at(row, 2),
            peso: Enum.at(row, 3),
            puntos: Enum.at(row, 4),
            alias: Enum.at(row, 5)
          }

        end)
    })

  end

end