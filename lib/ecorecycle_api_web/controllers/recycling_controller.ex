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
            NE.Id,
            (NE.PuntosMaximos - U.eco_points) AS PuntosFaltantes,
            (SELECT NombreNivel
            FROM NivelesEco
            WHERE Id = NE.Id + 1) AS SiguienteNivel,
            CONVERT(
                DECIMAL(10,2),
                (
                    CONVERT(
                        DECIMAL(10,2),
                        (U.eco_points - NE.PuntosMinimos)
                    )
                    /
                    CONVERT(
                        DECIMAL(10,2),
                        (NE.PuntosMaximos - NE.PuntosMinimos)
                    )
                ) * 100
            ) AS Progreso
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
          idlevel: Enum.at(row, 6),

          puntosfaltantes: Enum.at(row,7 ),
          siguientenivel: Enum.at(row,8 ),
          progreso: Enum.at(row,9 )
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


  # =========================================
  # LISTA
  # =========================================
  def recojos_asignados(conn, _params) do

  query = """

  SELECT

      sr.Codigo,

      sr.Transportista,

      cr.TipoMaterial,

      sr.PesoTotal,

      sr.FechaRecojo,

      sr.Horario,

      sr.Estado

  FROM SolicitudRecojo sr

  INNER JOIN ContenedorReciclaje cr
      ON cr.Id = sr.ContenedorId

  WHERE sr.Estado = 'pendiente'

  ORDER BY sr.FechaRecojo ASC

  """

  case Ecto.Adapters.SQL.query(
    Repo,
    query,
    []
  ) do

    {:ok, result} ->

      data =

        Enum.map(
          result.rows,
          fn row ->

            %{

              codigo:
                Enum.at(row, 0),

              transportista:
                Enum.at(row, 1),

              material:
                Enum.at(row, 2),

              peso_total:
                Enum.at(row, 3),

              fecha_recojo:
                Enum.at(row, 4),

              horario:
                Enum.at(row, 5),

              estado:
                Enum.at(row, 6),
            }
          end
        )

      json(conn, data)

    {:error, error} ->

      json(conn, %{
        error:
          inspect(error)
      })
  end
end

  # =========================================
  # CONFIRMAR
  # =========================================
  def confirmar_recojo(conn, %{"codigo" => codigo}) do

    {:ok, _} =
      Repo.query("""

      UPDATE SolicitudRecojo

      SET
        Estado = 'recolectado',
        FechaRecojoReal = GETDATE()

      WHERE Codigo = @1

      """, [codigo])

    json(conn, %{
      success: true
    })
  end

def listar_incentivos(conn, params) do

  usuario_id =
    Map.get(params, "usuario_id")

  query = """

  SELECT

      i.Id,
      i.Nombre,
      i.Descripcion,
      i.EcoPuntosRequeridos,

      u.eco_points

  FROM Incentivo i

  CROSS JOIN Users u

  WHERE
      i.Estado = 'activo'
      AND u.Id = @1

  """

  case Ecto.Adapters.SQL.query(
    Repo,
    query,
    [usuario_id]
  ) do

    {:ok, result} ->

      data =

        Enum.map(
          result.rows,
          fn row ->

            puntos_usuario =
              Enum.at(row, 4)

            puntos_requeridos =
              Enum.at(row, 3)

            habilitado =
              puntos_usuario >= puntos_requeridos

            faltantes =
              puntos_requeridos - puntos_usuario

            %{

              id:
                Enum.at(row, 0),

                nombre:
                  Enum.at(row, 1)
                  |> :unicode.characters_to_binary(:latin1, :utf8),

                descripcion:
                  Enum.at(row, 2)
                  |> :unicode.characters_to_binary(:latin1, :utf8),

              ecopuntos_requeridos:
                puntos_requeridos,

              ecopuntos_usuario:
                puntos_usuario,

              habilitado:
                habilitado,

              faltantes:
                if(
                  habilitado,
                  do: 0,
                  else: faltantes
                )
            }
          end
        )

      json(conn, data)

    {:error, error} ->

      json(conn, %{
        error: inspect(error)
      })
  end
end

def canjear_incentivo(conn, params) do

  usuario_id =
    params["usuario_id"]

  incentivo_id =
    params["incentivo_id"]

  query = """

  SELECT

      EcoPuntosRequeridos

  FROM Incentivo

  WHERE Id = @1

  """

  {:ok, result} =
    Ecto.Adapters.SQL.query(
      Repo,
      query,
      [incentivo_id]
    )

  puntos =
    result.rows
    |> List.first()
    |> List.first()

  query_user = """

  SELECT eco_points

  FROM Users

  WHERE Id = @1

  """

  {:ok, user_result} =
    Ecto.Adapters.SQL.query(
      Repo,
      query_user,
      [usuario_id]
    )

  eco_points =
    user_result.rows
    |> List.first()
    |> List.first()

  if eco_points < puntos do

    json(conn, %{
      success: false,
      message: "Puntos insuficientes"
    })

  else

    descuento_query = """

    UPDATE Users

    SET eco_points = eco_points - @1

    WHERE Id = @2

    """

    Ecto.Adapters.SQL.query(
      Repo,
      descuento_query,
      [puntos, usuario_id]
    )

    insert_query = """

    INSERT INTO Canje
    (
      UsuarioId,
      IncentivoId,
      EcoPuntosUsados,
      Estado
    )

    OUTPUT INSERTED.Id

    VALUES
    (
      @1,
      @2,
      @3,
      'realizado'
    )

    """

    {:ok, insert_result} =
      Ecto.Adapters.SQL.query(
        Repo,
        insert_query,
        [
          usuario_id,
          incentivo_id,
          puntos
        ]
      )

    canje_id =
      insert_result.rows
      |> List.first()
      |> List.first()

    # ============================================
# GENERAR CODIGO
# ============================================

fecha =
  Date.utc_today()
  |> Date.to_string()
  |> String.replace("-", "")

codigo =
  "CANJE-#{fecha}-#{canje_id}"

    update_query = """

    UPDATE Canje

    SET CodigoCanje = @1

    WHERE Id = @2

    """

    Ecto.Adapters.SQL.query(
      Repo,
      update_query,
      [codigo, canje_id]
    )

    json(conn, %{
      success: true,
      codigo: codigo
    })
  end
end

# =========================================================
# RANKING BLOQUES
# =========================================================

def ranking_bloques(conn, params) do
  fecha_inicio = params["fecha_inicio"]
  fecha_fin = params["fecha_fin"]

  query = """
SELECT
    BM.Name AS bloque,

    SUM(ISNULL(SRD.Puntos, 0)) AS ecopuntos,

    SUM(ISNULL(SR.PesoTotal, 0)) AS peso_reciclado,

    SUM(ISNULL(SR.ValorTotal, 0)) AS valor_economico,

    COUNT(SR.Id) AS entregas,

    MAX(NE.NombreNivel) AS nivel_promedio

FROM SolicitudReciclaje SR

INNER JOIN SolicitudReciclajeDetalle SRD
    ON SRD.SolicitudId = SR.Id

INNER JOIN Users U
    ON U.id = SR.UsuarioId

INNER JOIN NivelesEco NE
    ON U.eco_points BETWEEN NE.PuntosMinimos AND NE.PuntosMaximos

INNER JOIN UnitManagement UM
    ON UM.IdUnitManagement = U.UnitManagement

INNER JOIN BlockManagement BM
    ON BM.IdBlockManager = UM.IdBlockManager

WHERE
    SR.Estado = 'aprobado'
    AND CAST(SR.FechaRegistro AS DATE)
        BETWEEN @1 AND @2

GROUP BY BM.Name

ORDER BY ecopuntos DESC
"""

  {:ok, result} =
    Ecto.Adapters.SQL.query(
      Repo,
      query,
      [fecha_inicio, fecha_fin]
    )

rows =
  result.rows
  |> Enum.with_index(1)
  |> Enum.map(fn {row, index} ->
    %{
      posicion: index,
      bloque: Enum.at(row, 0),
      ecopuntos: Enum.at(row, 1),
      peso_reciclado: Enum.at(row, 2),
      valor_economico: Enum.at(row, 3),
      entregas: Enum.at(row, 4),
      nivel_promedio: Enum.at(row, 5)
    }
  end)

  json(conn, rows)
end

def guardar_token(conn, params) do
  user_id = params["user_id"]
  token = params["token"]

  query = """
  UPDATE Users
  SET FirebaseToken = @1
  WHERE id = @2
  """

  Ecto.Adapters.SQL.query!(
    Repo,
    query,
    [token, user_id]
  )

  json(conn, %{
    success: true
  })
end

# =========================================================
# HISTORIAL ECOBENEFICIOS
# =========================================================

def historial_ecobeneficios(conn, %{"user_id" => user_id}) do

  {:ok, result} =
    Repo.query(
      """
      SELECT
          EC.CodigoCanje,

          I.nombre AS Beneficio,

          EC.EcoPuntosUsados,

          FORMAT(
              EC.FechaCanje,
              'yyyy/MM/dd - HH:mm'
          ) AS FechaCanje,

          EC.Estado

      FROM Canje EC

      INNER JOIN Incentivo I
          ON I.id = EC.IncentivoId

      WHERE EC.UsuarioId = @1

      ORDER BY EC.FechaCanje DESC
      """,
      [user_id]
    )

  historial =
  Enum.map(result.rows, fn row ->
    %{
      codigo:
        Enum.at(row, 0)
        |> :unicode.characters_to_binary(:latin1, :utf8),

      beneficio:
        Enum.at(row, 1)
        |> :unicode.characters_to_binary(:latin1, :utf8),

      ecopuntos: Enum.at(row, 2),

      fecha:
        Enum.at(row, 3)
        |> :unicode.characters_to_binary(:latin1, :utf8),

      estado:
        Enum.at(row, 4)
        |> :unicode.characters_to_binary(:latin1, :utf8)
    }
  end)

  # ==========================================
  # RESUMEN
  # ==========================================

  {:ok, resumenQuery} =
    Repo.query(
      """
      SELECT

          COUNT(*) AS TotalCanjes,

          SUM(
              ISNULL(EcoPuntosUsados,0)
          ) AS TotalEcoPuntos,

          SUM(
              CASE
                  WHEN Estado = 'realizado'
                  THEN 1
                  ELSE 0
              END
          ) AS BeneficiosActivos

      FROM Canje

      WHERE UsuarioId = @1
      """,
      [user_id]
    )

  resumenRow =
    List.first(resumenQuery.rows)

  resumen = %{
    total_beneficios:
      Enum.at(resumenRow, 0) || 0,

    total_ecopuntos:
      Enum.at(resumenRow, 1) || 0,

    beneficios_activos:
      Enum.at(resumenRow, 2) || 0
  }

  json(conn, %{
    success: true,
    historial: historial,
    resumen: resumen
  })
end

# =========================================================
# LISTAR CAMPAÑAS
# =========================================================

def listar_campanias(conn, _params) do

# ============================================
# FINALIZAR CAMPAÑAS VENCIDAS
# ============================================

Repo.query!(
  """
  UPDATE campanias
  SET Estado = 'finalizado'
  WHERE
      Estado = 'activa'
      AND FechaFin < CAST(GETDATE() AS DATE)
  """
)

  {:ok, result} =
    Repo.query(
      """
      SELECT

          C.IdCampania,

          C.NombreCampania,

          C.Incentivo,

          FORMAT(
              C.FechaInicio,
              'yyyy/MM/dd'
          ) AS FechaInicio,

          FORMAT(
              C.FechaFin,
              'yyyy/MM/dd'
          ) AS FechaFin,

          C.MaterialObjetivo,

          C.Estado,

          (
            SELECT COUNT(*)
            FROM SolicitudReciclaje SR
            INNER JOIN SolicitudReciclajeDetalle SRD
              ON SRD.SolicitudId = SR.Id

            WHERE
                SR.Estado = 'aprobado'
                AND SRD.TipoReciclaje = C.MaterialObjetivo
                AND CAST(SR.FechaRegistro AS DATE)
                  BETWEEN C.FechaInicio
                  AND C.FechaFin
          ) AS Entregas,

          (
            SELECT
                ISNULL(SUM(SRD.Puntos),0)

            FROM SolicitudReciclaje SR
            INNER JOIN SolicitudReciclajeDetalle SRD
              ON SRD.SolicitudId = SR.Id

            WHERE
                SR.Estado = 'aprobado'
                AND SRD.TipoReciclaje = C.MaterialObjetivo
                AND CAST(SR.FechaRegistro AS DATE)
                  BETWEEN C.FechaInicio
                  AND C.FechaFin
          ) AS EcoPuntos

      FROM Campanias C

      ORDER BY C.IdCampania DESC
      """
    )

  campañas =
    Enum.map(result.rows, fn row ->

      %{
        id: Enum.at(row, 0),

        nombre: Enum.at(row, 1),

        descripcion: Enum.at(row, 2),

        fecha_inicio: Enum.at(row, 3),

        fecha_fin: Enum.at(row, 4),

        material: Enum.at(row, 5),

        estado: Enum.at(row, 6),

        entregas: Enum.at(row, 7),

        ecopuntos: Enum.at(row, 8)
      }

    end)

  json(conn, campañas)
end

# =========================================================
# CREAR CAMPAÑA
# =========================================================

def crear_campania(conn, params) do

  Repo.query!(
    """
    INSERT INTO Campanias
    (
      NombreCampania,
      Incentivo,
      FechaInicio,
      FechaFin,
      MaterialObjetivo,
      Estado
    )
    VALUES
    (
      @1,
      @2,
      @3,
      @4,
      @5,
      'activo'
    )
    """,
    [
      params["nombre"],
      params["descripcion"],
      params["fecha_inicio"],
      params["fecha_fin"],
      params["material"]
    ]
  )

  json(conn, %{
    success: true
  })
end

# =========================================================
# EDITAR CAMPAÑA
# =========================================================

def editar_campania(conn, %{"id" => id} = params) do

  Repo.query!(
    """
    UPDATE Campanias
    SET

      NombreCampania = @1,

      Incentivo = @2,

      FechaInicio = @3,

      FechaFin = @4,

      MaterialObjetivo = @5

    WHERE IdCampania = @6
    """,
    [
      params["nombre"],
      params["descripcion"],
      params["fecha_inicio"],
      params["fecha_fin"],
      params["material"],
      id
    ]
  )

  json(conn, %{
    success: true
  })
end

# =========================================================
# ELIMINAR CAMPAÑA
# =========================================================

def eliminar_campania(conn, %{"id" => id}) do

  Repo.query!(
    """
    DELETE FROM Campanias
    WHERE IdCampania = @1
    """,
    [id]
  )

  json(conn, %{
    success: true
  })
end

# =========================================================
# DESACTIVAR CAMPAÑA
# =========================================================

def desactivar_campania(conn, %{"id" => id}) do

  Repo.query!(
    """
    UPDATE Campanias
    SET Estado = 'desactivado'
    WHERE IdCampania = @1
    """,
    [id]
  )

  json(conn, %{
    success: true
  })
end

end