import Config

if config_env() == :prod do

  port =
    String.to_integer(
      System.get_env("PORT") || "4000"
    )

  config :ecorecycle_api,
    EcorecycleApiWeb.Endpoint,
    server: true,
    http: [
      ip: {0,0,0,0},
      port: port
    ]

  config :ecorecycle_api,
    EcorecycleApi.Repo,
    username: System.get_env("DB_USER"),
    password: System.get_env("DB_PASS"),
    hostname: System.get_env("DB_HOST"),
    database: System.get_env("DB_NAME"),
    port: 1433,
    pool_size: 10

end