defmodule ShadowSocks do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    import ShadowSocks.Config

    opts = Application.get_env(:shadowsocks, :server)

    port = int "SHADOW_PORT", opts.port
    password = string "SHADOW_PASS", opts.password
    key_length = int "SHADOW_KEYLEN", opts.key_length
    iv_length = int "SHADOW_IVLEN", opts.iv_length

    {key, iv} = ShadowSocks.Coder.evp_bytes_to_key(password, key_length, iv_length)

    children = [
      # Define workers and child supervisors to be supervised
      worker(ShadowSocks.Supervisor, [port, key, iv])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShadowSocks.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
