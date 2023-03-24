# to run:
# > elixir --no-halt udp_tunnel.exs
# to test:
# > echo "hello world" | nc -u -w0 localhost 51820
# > echo "quit" | nc -u -w0 localhost 51820

# Let's call our module "UDPTunnel"
defmodule UDPTunnel do
  # Our module is going to use the DSL (Domain Specific Language) for Gen(eric) Servers
  use GenServer

  @udp_port 51821

  # We need a factory method to create our server process
  # it takes a single parameter `port` which defaults to `51820`
  # This runs in the caller's context
  def start_link(options) do
    GenServer.start_link(__MODULE__, options) # Start 'er up
  end

  def is_tcp_server?(%{options: options}) do
    !!Keyword.get(options, :server)
  end

  def is_tcp_client?(%{options: options}) do
    !!Keyword.get(options, :client)
  end

  # Initialization that runs in the server context (inside the server process right after it boots)
  def init(options) do
    state = %{options: options}
    log(state, "UDP tunnel initializing")

    # Use erlang's `gen_udp` module to open a socket
    # With options:
    #   - binary: request that data be returned as a `String`
    #   - active: gen_udp will handle data reception, and send us a message `{:udp, socket, address, port, data}` when new data arrives on the socket
    # Returns: {:ok, socket}
    cond do
      is_tcp_server?(state) && is_tcp_client?(state) ->
        IO.puts "Error, got a server and client argument, can only have one"
        {:stop, :normal, nil}
      is_tcp_server?(state) ->
        {:ok, listen_socket} = :gen_tcp.listen(@udp_port, [active: true])
        {:ok, server_socket } = :gen_tcp.accept listen_socket

        {:ok, Map.put(state, :server_socket, server_socket)}
      is_tcp_client?(state) ->
#        {:ok, } - :gen_tcp.connect()
        {:ok, server_socket} = :gen_udp.open(@udp_port, [active: true])
        {:ok, Map.put(state, :server_socket, server_socket)}
    end
  end

  def handle_info({:tcp,socket,packet},state) do
    IO.inspect packet, label: "incoming packet"
    {:noreply, state}
  end

  def handle_info({:tcp_closed,socket},state) do
    IO.inspect "Socket has been closed"
    {:noreply, state}
  end

  def handle_info({:tcp_error,socket,reason},state) do
    IO.inspect socket , label: "connection closed due to #{reason}"
    {:noreply, state}
  end

  defp log(%{options: options}, message) do
    if Keyword.get(options, :verbose) do
      IO.puts message
    end
  end

  # define a callback handler for when gen_udp sends us a UDP packet
  def handle_info({:tcp, _socket, _address, _port, data}, state) do
    # punt the data to a new function that will do pattern matching
    IO.inspect(data)
    {:noreply, state}
  end

  # define a callback handler for when gen_udp sends us a UDP packet
  def handle_info({:udp, _socket, _address, _port, data}, state) do
    # punt the data to a new function that will do pattern matching
    handle_udp_packet(data, state)
  end

  # fallback pattern match to handle all other (non-"quit") messages
  defp handle_udp_packet(data, state) do
    # print the message
    encoded_data =
      data
      |> to_string()
      |> Base.encode64

    IO.puts("Received: #{data}")

    # IRL: do something more interesting...

    # GenServer will understand this to mean "continue waiting for the next message"
    # parameters:
    # :noreply - no reply is needed
    # new_state: keep the state as the current state
    {:noreply, state}
  end
end

# For extra protection, start a supervisor that will start the UDPTunnel
# The supervisor's job is to monitor the UDPTunnel
# If it crashes it will auto restart, fault tolerance in 1 line of code!!!
{parsed_options, args, invalid} = OptionParser.parse(System.argv(), strict: [verbose: :boolean, help: :boolean, server: :integer, client: :integer])

if Keyword.get(parsed_options, :help) do
  IO.puts "UDP Tunnel Help"
else
  System.no_halt(true)
  {:ok, pid} = Supervisor.start_link([{UDPTunnel, parsed_options}], strategy: :one_for_one)
  Process.unlink(pid) # unlink so if this proccess finishes it wont take down the UDP tunnel as well
end
