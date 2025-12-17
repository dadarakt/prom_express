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

  @doc """
  Emits an event-based metric defined in the calling module.

  This macro emits a `:telemetry` event corresponding to an `event_metric/3`
  declared in the same module that calls this macro.

  The metric name must be known at compile time when given as a literal atom.
  If an unknown metric name is used, compilation will fail with an error.

  ### Arguments

    * `name` – the name of the event metric (atom)
    * `value` – the metric value to emit
    * `metadata` – optional map of metadata used as metric tags

  ### Examples

  ```
  defmodule MyEmitter do
    use PromExpress.Emitter

    event_metric :requests, :counter, tags: [:status]

    def record_request(status) do
      PromExpress.metric_event(:requests, 1, %{status: status})
    end
  end
  ```

  When called, this emits a telemetry event of the form:

  ```
  [:root_event, :my_emitter, :requests]
  ```
  with measurements `%{value: value}` and the given metadata.
  """
  defmacro metric_event(name_ast, value_ast, metadata_ast \\ quote(do: %{})) do
    caller = __CALLER__.module
    root_event = Module.get_attribute(caller, :root_event)

    raw_defs = Module.get_attribute(caller, :event_metrics_def) || []
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

  @doc """
  Emits an event-based metric defined in another module.

  This macro allows emitting an `event_metric/3` that was declared in a different
  module using `PromExpress.Emitter`.

  When both the target module and metric name are given as literal atoms, the
  macro validates at compile time that the metric exists in the target module.
  If it does not, compilation fails with an error.

  ### Arguments

    * `module` – the module that defines the event metric
    * `name` – the name of the event metric (atom)
    * `value` – the metric value to emit
    * `metadata` – optional map of metadata used as metric tags

  ### Examples

  ```
  defmodule MyEmitter do
    use PromExpress.Emitter

    event_metric :requests, :counter, tags: [:status]
  end

  defmodule MyWorker do
    require PromExpress

    def record_request(status) do
      PromExpress.metric_event_in(MyEmitter, :requests, 1, %{status: status})
    end
  end
  ```

  This emits the same telemetry event as if it were emitted from MyEmitter
  itself, using the event name:

  ```
    [:root_event, :my_emitter, :requests]
  ```

  ### Notes
  This macro must be invoked from a module that requires PromExpress.

  Compile-time validation is skipped when the module or metric name is dynamic.
  """
  defmacro metric_event_in(mod_ast, name_ast, value_ast, metadata_ast \\ quote(do: %{})) do
    expanded_mod = Macro.expand(mod_ast, __CALLER__)

    case {expanded_mod, name_ast} do
      {mod, n} when is_atom(mod) and is_atom(n) ->
        unless Code.ensure_loaded?(mod) do
          raise ArgumentError, "metric_event_in/4: module #{inspect(mod)} is not loaded"
        end

        if function_exported?(mod, :__promexpress_defined_event_metrics__, 0) do
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
      mod = unquote(mod_ast)
      base = mod.__promexpress_event_base__()

      unquote(
        emit_telemetry_ast(
          quote(do: base ++ [unquote(name_ast)]),
          value_ast,
          metadata_ast
        )
      )
    end
  end

  @doc """
  Used to retrieve all modules which emit metrics.
  Intended usage is to add them to your `PromEx` plugins list:

  ```
  @impl true
  def plugins do
    [
      Plugins.Application,
      ...
    ] ++ PromExpress.metric_plugins()
  end
  ```

  If preferred, you can simply add the modules manually to the plugin list.
  """
  def metric_plugins() do
    app = Mix.Project.config()[:app]
    {:ok, mods} = :application.get_key(app, :modules)

    for mod <- mods,
        Code.ensure_loaded?(mod),
        function_exported?(mod, :__info__, 1),
        attrs = mod.__info__(:attributes),
        true in Keyword.get(attrs, :prom_ex_plugin, []),
        function_exported?(mod, :polling_metrics, 1),
        function_exported?(mod, :event_metrics, 1) do
      mod
    end
  end
end
