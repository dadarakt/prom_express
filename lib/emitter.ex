defmodule PromExpress.Emitter do
  @moduledoc """
  Use this in a module that defines metrics for PromEx.

  It provides:

    * `polling_metric/3` — describe **polling** metrics at compile time
    * `event_metric/3`   — describe **event-based** metrics at compile time

  When polling_metrics are added, a function `poll_metrics/1` is required, which returns a
  map keyed with the names of the `polling_metric`s.

  Example:
      defmodule MyEmitter do
        use PromExpress.Emitter, poll_rate: 10_000

        polling_metric :foo, :last_value,
          description: "Current foo value"

        event_metric :bar, :counter,
          description: "Number of bars",
          tags: [:type]

        def poll_metrics() do
          %{foo: 42}
        end

        def some_function(type) do
          metric_event(:bar, 1, %{type: type})
        end
      end

  Look into the promex documentation for more on all the types of metrics and their respective options.
  """

  @callback poll_metrics() :: map()

  defmacro __using__(opts) do
    poll_rate  = Keyword.get(opts, :poll_rate, 5_000)

    root_event =
      Keyword.get(opts, :root_event,
        Mix.Project.config()[:app] ||
          raise("Cannot infer app name, please provide `root_event` for metrics")
      )

    quote do
      require PromExpress
      import PromExpress, only: [metric_event: 2, metric_event: 3]

      import unquote(__MODULE__), only: [
        polling_metric: 2,
        polling_metric: 3,
        event_metric: 2,
        event_metric: 3
      ]

      Module.register_attribute(__MODULE__, :metrics_def,       accumulate: true)
      Module.register_attribute(__MODULE__, :event_metrics_def, accumulate: true)

      @poll_rate  unquote(poll_rate)
      @root_event unquote(root_event)

      @before_compile unquote(__MODULE__)
    end
  end

  @doc """
  A polling metrics are periodically (poll_rate option of this macro) collected instead of emitted via events.
  `poll_metrics` must return a value for the name of each metric, and can additionally provide tags for labelling
  of data.
  """
  defmacro polling_metric(name, type) when is_atom(name) and is_atom(type) do
    quote do
      @metrics_def {unquote(name), unquote(type), []}
    end
  end
  defmacro polling_metric(name, type, opts)
           when is_atom(name) and is_atom(type) and is_list(opts) do
    quote do
      @metrics_def {unquote(name), unquote(type), unquote(opts)}
    end
  end
  defmacro polling_metric(_name, _type, bad_opts) do
  raise ArgumentError,
        "polling_metric/3 expects the 3rd argument to be a keyword list, got: #{Macro.to_string(bad_opts)}"
  end

  @doc """
  Event metrics are metrics which are emitted dynamically from the code.
  They require a value and can optionally have a set of tags to label data points.
  """
  defmacro event_metric(name, type) when is_atom(name) and is_atom(type) do
    quote do
      @event_metrics_def {unquote(name), unquote(type), []}
    end
  end
  defmacro event_metric(name, type, opts)
           when is_atom(name) and is_atom(type) and is_list(opts) do
    quote do
      @event_metrics_def {unquote(name), unquote(type), unquote(opts)}
    end
  end
  defmacro event_metric(_name, _type, bad_opts) do
  raise ArgumentError,
        "event_metric/3 expects the 3rd argument to be a keyword list, got: #{Macro.to_string(bad_opts)}"
  end

  defmacro __before_compile__(env) do
    caller          = env.module
    polling_metrics = Module.get_attribute(caller, :metrics_def)       || []
    event_metrics   = Module.get_attribute(caller, :event_metrics_def) || []
    poll_rate       = Module.get_attribute(caller, :poll_rate)
    root_event      = Module.get_attribute(caller, :root_event)

    last_segment = caller |> Module.split() |> List.last()
    snake        = last_segment |> Macro.underscore() |> String.to_atom()

    if polling_metrics != [] and not Module.defines?(caller, {:poll_metrics, 0}, :def) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(caller)} defines polling_metric/3 but does not implement poll_metrics/0. Please add an implementation."
    end

    polling_metrics =
      Enum.map(polling_metrics, fn
        {name, type, nil} ->
          {name, type, []}

        {name, type, opts} when is_list(opts) ->
          {name, type, opts}

        {name, _type, bad_opts} ->
          raise CompileError,
            file: env.file,
            line: env.line,
            description:
              "Invalid options for polling_metric #{inspect(name)}. " <>
              "Expected a keyword list, got: #{Macro.to_string(bad_opts)}"
      end)

    event_metrics =
      Enum.map(event_metrics, fn
        {name, type, nil} ->
          {name, type, []}

        {name, type, opts} when is_list(opts) ->
          {name, type, opts}

        {name, _type, bad_opts} ->
          raise CompileError,
            file: env.file,
            line: env.line,
            description:
              "Invalid options for event_metric #{inspect(name)}. " <>
              "Expected a keyword list, got: #{Macro.to_string(bad_opts)}"
      end)

    poll_event = [root_event, snake]

    polling_metrics_ast =
      for {name, type, opts} <- polling_metrics do
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
      if polling_metrics == [] do
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
            polled_metrics = unquote(caller).poll_metrics()
            :telemetry.execute(@poll_event_base, polled_metrics, %{})
          end
        end
      end

    defined_event_names = Enum.map(event_metrics, fn {n, _t, _o} -> n end)

    quote do
      use PromEx.Plugin
      import Telemetry.Metrics
      alias PromEx.MetricTypes.Polling
      alias PromEx.MetricTypes.Event

      Module.register_attribute(__MODULE__, :prom_ex_plugin, persist: true)
      @prom_ex_plugin true

      @poll_event_base unquote(poll_event)
      @poll_rate       unquote(poll_rate)

      @doc false
      def __promexpress_event_base__(), do: unquote(poll_event)

      @doc false
      def __promexpress_defined_event_metrics__(), do: unquote(defined_event_names)

      unquote(polling_fun_ast)
      unquote(event_metrics_fun_ast)
    end
  end
end
