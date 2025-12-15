defmodule PromExpress do
  @moduledoc """
  Helpers for emitting metrics from modules that `use PromExpress.Emitter`.
  """

  defmacro metric_event(name_ast, value, metadata \\ quote(do: %{})) do
    caller     = __CALLER__.module
    root_event = Module.get_attribute(caller, :root_event)

    # Read the event metric definitions from the caller module
    raw_defs      = Module.get_attribute(caller, :event_metrics_def) || []
    defined_names = Enum.map(raw_defs, fn {n, _type, _opts} -> n end)

    # Compile-time validation for literal atoms
    case name_ast do
      n when is_atom(n) ->
        unless n in defined_names do
          raise ArgumentError,
                "Unknown event metric #{inspect(n)} in #{inspect(caller)}. " <>
                  "Defined event_metric names: #{inspect(defined_names)}"
        end

      _ ->
        :ok
    end

    last_segment =
      caller
      |> Module.split()
      |> List.last()

    snake = last_segment |> Macro.underscore() |> String.to_atom()

    # Must match per-metric event_name in Definition:
    #   [:root_event, snake, name]
    event_name = [root_event, snake, name_ast]

    quote do
      :telemetry.execute(
        unquote(event_name),
        %{value: unquote(value)},
        unquote(metadata)
      )
    end
  end
end
