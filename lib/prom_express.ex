defmodule PromExpress do
  @moduledoc """
  Helpers for emitting metrics from modules that `use PromExpress.Emitter`.
  """

  defp emit_telemetry_ast(event_name_ast, value_ast, metadata_ast) do
    quote do
      :telemetry.execute(
        unquote(event_name_ast),
        %{value: unquote(value_ast)},
        unquote(metadata_ast)
      )
    end
  end

  defmacro metric_event(name_ast, value_ast, metadata_ast \\ quote(do: %{})) do
    caller     = __CALLER__.module
    root_event = Module.get_attribute(caller, :root_event)

    raw_defs      = Module.get_attribute(caller, :event_metrics_def) || []
    defined_names = Enum.map(raw_defs, fn {n, _type, _opts} -> n end)

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

    snake =
      caller
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()

    event_name_ast = [root_event, snake, name_ast]
    emit_telemetry_ast(event_name_ast, value_ast, metadata_ast)
  end

  defmacro metric_event_in(mod_ast, name_ast, value_ast, metadata_ast \\ quote(do: %{})) do
    case {mod_ast, name_ast} do
      {mod, n} when is_atom(mod) and is_atom(n) ->
        if Code.ensure_loaded?(mod) and function_exported?(mod, :__promexpress_defined_event_metrics__, 0) do
          defined = mod.__promexpress_defined_event_metrics__()
          unless n in defined do
            raise ArgumentError,
                  "Unknown event metric #{inspect(n)} in #{inspect(mod)}. " <>
                    "Defined event_metric names: #{inspect(defined)}"
          end
        end

      _ ->
        :ok
    end

    quote do
      mod  = unquote(mod_ast)
      base = mod.__promexpress_event_base__() # [root_event, snake]
      unquote(
        emit_telemetry_ast(
          quote(do: base ++ [unquote(name_ast)]),
          value_ast,
          metadata_ast
        )
      )
    end
  end
end
