defmodule EcorecycleApiWeb.Router do
  use EcorecycleApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

 scope "/api", EcorecycleApiWeb do
  pipe_through :api

  post "/analyze", AnalyzeController, :analyze

  post "/recycling/save", RecyclingController, :save

  post "/auth/register", AuthController, :register
  post "/auth/login", AuthController, :login

  post "/historial/guardar", HistorialController, :guardar

  get "/historial/pendientes", HistorialController, :pendientes

post "/admin/aprobar/:id", AdminController, :aprobar

post "/admin/rechazar/:id", AdminController, :rechazar

get "/admin/pendientes", AdminController, :pendientes

get "/ranking", RankingController, :ranking

get "/user/profile/:id", RecyclingController, :perfil

get "/user/historial/:id", UserController, :historial

get "/user/solicitud/:id", RecyclingController, :detalle_solicitud

get "admin/contenedores", AdminController, :contenedores

post "admin/recojo", AdminController, :recojo

get "admin/transportistas", AdminController, :transportistas

get "/admin/seguimiento-entregas", AdminController, :seguimiento_entregas

get "/admin/historial-participacion",
      AdminController,
      :historial_participacion

get "/user/mis-ecopuntos", UserController, :mis_ecopuntos

get "user/mi-evolucion", UserController, :mi_evolucion

get "/user/categorias-reciclaje", UserController, :categorias_reciclaje

get "admin/reporte-consolidado",  AdminController, :reporte_consolidado

get "admin/reporte-bloques", AdminController, :reporte_bloques

get "admin/evolucion-material", AdminController, :evolucion_material

get "admin/entregas-transportador", AdminController, :entregas_transportador

get "user/notificaciones_campanas", UserController, :notificaciones_campanas

post "pickup/confirmar_recojo/:codigo", RecyclingController, :confirmar_recojo

get "pickup/recojos_asignados", RecyclingController, :recojos_asignados

get "/eco/incentivos", RecyclingController, :listar_incentivos

post "/eco/canjear", RecyclingController,  :canjear_incentivo

get "/admin/ranking_bloques", RecyclingController, :ranking_bloques

post "/guardar-token", RecyclingController, :guardar_token

get "/eco/historial-beneficios", RecyclingController, :historial_ecobeneficios

# ==========================================
# CAMPAÑAS
# ==========================================

get "/campanias",
    RecyclingController,
    :listar_campanias

post "/campanias",
    RecyclingController,
    :crear_campania

put "/campanias/:id",
    RecyclingController,
    :editar_campania

delete "/campanias/:id",
    RecyclingController,
    :eliminar_campania

put "/campanias/desactivar/:id",
    RecyclingController,
    :desactivar_campania

end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ecorecycle_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: EcorecycleApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
