defmodule Engine.Viber do
  @moduledoc """
    The module set webhook for the viber bots and sends custom messages
  """

  alias Agala.{BotParams, Conn}
  alias Agala.Bot.Handler
  alias Engine.Viber.{MessageSender, RequestHandler}

  use GenServer

  @url :viber_engine |> Application.get_env(Engine.Viber) |> Keyword.get(:url)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [name: :"#Engine.Viber::#{opts.name}"])
  end

  def init(opts) do
    set_webhook(opts)

    {:ok, opts}
  end

  def message_pass(bot_name, hub, message) do
    GenServer.cast(:"#Engine.Viber::#{bot_name}", {:message, hub, message})
  end

  def message_pass(bot_name, message) do
    GenServer.cast(:"#Engine.Viber::#{bot_name}", {:message, message})
  end

  def handle_cast({:message, %{"event" => event} = message}, state) when event == "webhook" do
    IO.puts "Webhook for #{state.provider_params.token} was set."
    {:noreply, state}
  end

  def handle_cast({:message, %{"event" => event, "message_token" => message_token, "user_id" => user_id} = _}, state) when event in ["delivered", "seen"] do
    IO.puts "Message #{message_token} was #{event} for #{user_id}"
    {:noreply, state}
  end

  def handle_cast({:message, message}, state) do
    Handler.handle(message, state)
    {:noreply, state}
  end

  def handle_cast({:message, _hub, %{"data" => %{"messages" => messages, "chat" => %{"id" => id}}} =  _message}, state) do
    messages
    |> RequestHandler.parse_hub_response()
    |> Enum.filter(& &1)
    |> MessageSender.delivery(id, state)

    {:noreply, state}
  end

  def set_webhook(%BotParams{name: bot_name} = params) do
    conn = %Conn{request_bot_params: params} |> Conn.send_to(bot_name)

    HTTPoison.post(
      set_webhook_url(conn),
      webhook_upload_body(conn),
      webhook_header(conn)
    )
    |> IO.inspect
  end

  def base_url do
    "https://chatapi.viber.com/pa"
  end

  def set_webhook_url(_conn) do
    base_url() <> "/set_webhook"
  end

  defp webhook_upload_body(conn, opts \\ []),
       do: %{url: server_webhook_url(conn), send_name: true} |> Poison.encode!

  defp parse_body({:ok, resp = %HTTPoison.Response{body: body}}),
       do: {:ok, %HTTPoison.Response{resp | body: Poison.decode!(body)}}

  defp parse_body(default), do: default

  defp server_webhook_url(conn),
       do: @url <> conn.request_bot_params.provider_params.token

  defp webhook_header(conn) do
    [
      {"X-Viber-Auth-Token", to_string(conn.request_bot_params.provider_params.token)},
      {"Content-Type", "application/json"},
    ]
  end
end
