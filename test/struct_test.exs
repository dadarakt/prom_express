defmodule PromExpress.StructTest do
  use ExUnit.Case

  alias PromExpress.Test.CompilationHelper

  test "polling_metrics/1 includes a Polling build" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterPolling do
          use PromExpress.Emitter, root_event: :prom_express

          polling_metric(:test_a, :last_value, description: "A")
          def poll_metrics(), do: %{test_a: 42}
        end
      end,
      MyEmitterPolling
    )

    assert function_exported?(MyEmitterPolling, :__promexpress_defined_event_metrics__, 0)
    assert function_exported?(MyEmitterPolling, :__promexpress_event_base__, 0)

    [polling] = apply(MyEmitterPolling, :polling_metrics, [[]])
    assert match?(%PromEx.MetricTypes.Polling{}, polling)
  end

  test "event_metrics/1 includes an Event.build with Telemetry metric defs" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterEvents do
          use PromExpress.Emitter, root_event: :prom_express

          event_metric(:event_test, :counter,
            description: "Count events",
            tags: [:type]
          )
        end
      end,
      MyEmitterEvents
    )

    [event_group] = apply(MyEmitterEvents, :event_metrics, [[]])

    assert function_exported?(MyEmitterEvents, :__promexpress_defined_event_metrics__, 0)
    assert function_exported?(MyEmitterEvents, :__promexpress_event_base__, 0)

    assert match?(%PromEx.MetricTypes.Event{}, event_group)

    # Event struct contains a list of Telemetry.Metrics.* inside
    # Shape depends on PromEx version, but usually `event_group.metrics` exists.
    metrics = Map.fetch!(event_group, :metrics)
    assert Enum.any?(metrics, &match?(%Telemetry.Metrics.Counter{}, &1))

    counter = Enum.find(metrics, &match?(%Telemetry.Metrics.Counter{}, &1))

    assert counter.event_name == [:prom_express, :my_emitter_events, :event_test]
    assert counter.measurement == :value
    assert counter.tags == [:type]
    assert counter.description == "Count events"
  end

  test "metric_event_in/4 can emit another module's event metric" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterCross do
          use PromExpress.Emitter, root_event: :prom_express

          event_metric(:event_test, :counter,
            description: "Count events",
            tags: [:type]
          )
        end
      end,
      MyEmitterCross
    )

    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyCallerCross do
          require PromExpress

          def fire(type) do
            PromExpress.metric_event_in(MyEmitterCross, :event_test, 1, %{type: type})
          end
        end
      end,
      MyCallerCross
    )

    event_name = [:prom_express, :my_emitter_cross, :event_test]
    test_pid = self()
    handler_id = {__MODULE__, :cross_emit_test}

    :ok =
      :telemetry.attach(
        handler_id,
        event_name,
        &PromExpress.Test.TelemetryHandler.handle_event/4,
        test_pid
      )

    try do
      apply(MyCallerCross, :fire, [:abc])
      assert_receive {:telemetry, ^event_name, %{value: 1}, %{type: :abc}}, 1_000
    after
      :telemetry.detach(handler_id)
    end
  end

  test "metric_event_in/4 fails compilation for unknown event name when module + name are literals" do
    # First compile the emitter so it's loaded and exposes the defined event names.
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterCrossBad do
          use PromExpress.Emitter, root_event: :prom_express

          event_metric(:event_ok, :counter,
            description: "ok",
            tags: [:type]
          )
        end
      end,
      MyEmitterCrossBad
    )

    # Now compilation of the caller should fail because :does_not_exist isn't defined on the emitter.
    assert_raise ArgumentError, ~r/Unknown event metric :does_not_exist/, fn ->
      CompilationHelper.compile_and_get!(
        quote do
          defmodule MyCallerCrossBad do
            require PromExpress

            def fire(type) do
              PromExpress.metric_event_in(MyEmitterCrossBad, :does_not_exist, 1, %{type: type})
            end
          end
        end,
        MyCallerCrossBad
      )
    end
  end
end
