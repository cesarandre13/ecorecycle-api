defmodule EcorecycleApi.Repo do
  use Ecto.Repo,
    otp_app: :ecorecycle_api,
    adapter: Ecto.Adapters.Tds
end
