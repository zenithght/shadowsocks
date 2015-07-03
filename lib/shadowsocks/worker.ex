defmodule ShadowSocks.Worker do
  require Logger
  use GenServer

  def start_link(client, key, iv) do
    Logger.info "Worker #{inspect client} started"

    GenServer.start_link(__MODULE__, {client, key, iv})
  end

  @doc """
  Set coder, start receiving from client
  """
  def init({client, key, encode_iv}) do
    {:ok, decode_iv} = :gen_tcp.recv(client, :erlang.size(encode_iv))
    :gen_tcp.send(client, encode_iv)
    :ok = :inet.setopts(client, active: true)
    {:ok, {:init, client, nil, {key, encode_iv, ""}, {key, decode_iv, ""}}}
  end

  @doc """
  Handle first requests
  """
  def handle_info({:tcp, client, bytes}, {:init, client, nil, encoder, decoder}) do
    {new_decoder, decoded} = bytes
    |> ShadowSocks.Coder.decode(decoder)

    remote = decoded
    |> parse_header
    |> connect_remote

    Logger.info "Link started #{inspect remote}"

    {:noreply, {:stream, client, remote, encoder, new_decoder}}
  end

  @doc """
  Handle streaming requests
  """
  def handle_info({:tcp, client, bytes}, {:stream, client, remote, encoder, decoder}) do
    {new_decoder, decoded} = bytes
    |> ShadowSocks.Coder.decode(decoder)

    :ok = :gen_tcp.send(remote, decoded)
    {:noreply, {:stream, client, remote, encoder, new_decoder}}
  end

  @doc """
  Received remote response
  """
  def handle_info({:tcp, remote, bytes}, {:stream, client, remote, encoder, decoder}) do
    {new_encoder, encoded} = bytes
    |> ShadowSocks.Coder.encode(encoder)

    :ok = :gen_tcp.send(client, encoded)
    {:noreply, {:stream, client, remote, new_encoder, decoder}}
  end

  @doc """
  Client disconnect
  """
  def handle_info({:tcp_closed, client}, {_status, client, _remote, _encoder, _decoder} = state) do
    Logger.info "Worker #{inspect client} stop"
    {:stop, :normal, state}
  end

  @doc """
  Remote disconnect
  """
  def handle_info({:tcp_closed, remote}, {_status, _client, remote, _encoder, _decoder} = state) do
    Logger.info "Link #{inspect remote} stop"
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn "Got msg", msg
    {:noreply, state}
  end

  # Parse_header domain request
  defp parse_header(<<3, len, domain::binary-size(len), port::size(16), payload::binary>>) do
    {domain, port, payload}
  end

  defp parse_header(data) do
    Logger.error "Can't parse header:", data
    {:error, :unknown_header_type}
  end

  # Start connection to remote
  defp connect_remote({host, port, payload}) do
    {:ok, pid} = :gen_tcp.connect(to_char_list(host), port, [:binary,
      packet: :raw, active: true])
    :ok = :gen_tcp.send(pid, payload)
    pid
  end

end
