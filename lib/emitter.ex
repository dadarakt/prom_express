defmodule PromExpress.Emitter do
  @moduledoc """
  Use this in a module that defines metrics for PromEx.

  It provides:

    * `polling_metric/3` — describe **polling** metrics at compile time
    * `event_metric/3`   — describe **event-based** metrics at compile time

  Example:

      defmodule MyEmitter do
        use PromExpress.Emitter

        polling_metric :foo, :last_value,
          description: "Current foo value"

        event_metric :bar, :counter,
          description: "Number of bars",
          tags: [:type]

        def metrics do
          %{foo: 42}
        end

        def some_function(type) do
          PromExpress.metric_event(:bar, 1, %{type: type})
        end
      end
  """

  defmacro __using__(opts) do
    poll_rate  = Keyword.get(opts, :poll_rate, 5_000)

    root_event =
      Keyword.get(opts, :root_event,
        Mix.Project.config()[:app] ||
          raise("Cannot infer app name, please provide `root_event` for metrics")
      )

    quote do
      require PromExpress
      require PromExpress.Emitter

      import PromExpress, only: [metric_event: 2, metric_event: 3]

      # keep these attribute names stable
      Module.register_attribute(__MODULE__, :metrics_def,       accumulate: true)
      Module.register_attribute(__MODULE__, :event_metrics_def, accumulate: true)

      @poll_rate  unquote(poll_rate)
      @root_event unquote(root_event)

      import unquote(__MODULE__), only: [polling_metric: 3, event_metric: 3]

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro polling_metric(name, type, opts)
           when is_atom(name) and is_atom(type) and is_list(opts) do
    quote do
      @metrics_def {unquote(name), unquote(type), unquote(opts)}
    end
  end

  defmacro event_metric(name, type, opts)
           when is_atom(name) and is_atom(type) and is_list(opts) do
    quote do
      @event_metrics_def {unquote(name), unquote(type), unquote(opts)}
    end
  end

  defmacro __before_compile__(env) do
    caller        = env.module
    metrics       = Module.get_attribute(caller, :metrics_def)       || []
    event_metrics = Module.get_attribute(caller, :event_metrics_def) || []
    poll_rate     = Module.get_attribute(caller, :poll_rate)
    root_event    = Module.get_attribute(caller, :root_event)

    last_segment = caller |> Module.split() |> List.last()
    snake        = last_segment |> Macro.underscore() |> String.to_atom()

    # polling events use [:root_event, snake]
    poll_event = [root_event, snake]

    plugin_mod = Module.concat([PromExpress.Metrics, "#{last_segment}Metrics"])

    # ---- Polling metrics AST ----
    polling_metrics_ast =
      for {name, type, opts} <- metrics do
        metric_name = poll_event ++ [name]

        build_fun =
          case type do
            :last_value   -> :last_value
            :counter      -> :counter
            :summary      -> :summary
            :distribution -> :distribution
            :sum          -> :sum
            other ->
              raise ArgumentError,
                    "Unsupported polling metric type #{inspect(other)} for #{inspect(name)}"
          end

        quote do
          unquote(build_fun)(
            unquote(metric_name),
            Keyword.merge(
              [
                event_name:  @poll_event_base,
                # polling metrics expect a map like %{test_a: 1, test_b: 2}
                # measurement: :test_a / :test_b
                measurement: unquote(name)
              ],
              unquote(opts)
            )
          )
        end
      end

    # ---- Event metrics AST ----
    # IMPORTANT: each event metric gets its own telemetry event_name:
    #   [:root_event, snake, name]
    # and always uses measurement: :value
    event_telemetry_ast =
      for {name, type, opts} <- event_metrics do
        event_name  = [root_event, snake, name]
        metric_name = event_name

        build_fun =
          case type do
            :last_value   -> :last_value
            :counter      -> :counter
            :summary      -> :summary
            :distribution -> :distribution
            :sum          -> :sum
            other ->
              raise ArgumentError,
                    "Unsupported event metric type #{inspect(other)} for #{inspect(name)}"
          end

        quote do
          unquote(build_fun)(
            unquote(metric_name),
            Keyword.merge(
              [
                event_name:  unquote(event_name),
                measurement: :value
              ],
              unquote(opts)
            )
          )
        end
      end

    event_group_name = :"#{root_event}_#{snake}_event_metrics"

    event_metrics_fun_ast =
      if event_metrics == [] do
        quote do
          @impl true
          def event_metrics(_opts), do: []
        end
      else
        quote do
          @impl true
          def event_metrics(_opts) do
            [
              Event.build(
                unquote(event_group_name),
                [
                  unquote_splicing(event_telemetry_ast)
                ]
              )
            ]
          end
        end
      end

    polling_fun_ast =
      if metrics == [] do
        quote do
          @impl true
          def polling_metrics(_opts), do: []
        end
      else
        quote do
          @impl true
          def polling_metrics(_opts) do
            [
              build_polling(@poll_rate)
            ]
          end

          defp build_polling(poll_rate) do
            Polling.build(
              unquote(:"#{root_event}_#{snake}_polling_events"),
              poll_rate,
              {__MODULE__, :execute_metrics, []},
              [
                unquote_splicing(polling_metrics_ast)
              ]
            )
          end

          def execute_metrics() do
            metrics = unquote(caller).metrics()
            :telemetry.execute(@poll_event_base, metrics, %{})
          end
        end
      end

    quote do
      defmodule unquote(plugin_mod) do
        use PromEx.Plugin
        import Telemetry.Metrics
        alias PromEx.MetricTypes.Polling
        alias PromEx.MetricTypes.Event

        Module.register_attribute(__MODULE__, :prom_ex_plugin, persist: true)
        @prom_ex_plugin true

        @poll_event_base unquote(poll_event)
        @poll_rate       unquote(poll_rate)

        # Conditionally generated polling code
        unquote(polling_fun_ast)

        # Conditionally generated event code (your existing logic)
        unquote(event_metrics_fun_ast)
      end
    end
  end
end
