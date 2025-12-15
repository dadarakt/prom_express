defmodule PromExpress.StructTest do
  use ExUnit.Case

  alias PromExpress.Test.CompilationHelper

  test "polling_metrics/1 includes a Polling build" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterPolling do
          use PromExpress.Emitter, root_event: :prom_express, poll_rate: 10_000

          polling_metric :test_a, :last_value, description: "A"
          def poll_metrics(), do: %{test_a: 42}
        end
      end,
      MyEmitterPolling
    )

    plugin = Module.concat([PromExpress.Metrics, "MyEmitterPolling"])
    [polling] = plugin.polling_metrics([])

    # PromEx.MetricTypes.Polling struct
    assert match?(%PromEx.MetricTypes.Polling{}, polling)
  end

  test "event_metrics/1 includes an Event.build with Telemetry metric defs" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterEvents do
          use PromExpress.Emitter, root_event: :prom_express

          event_metric :event_test, :counter,
            description: "Count events",
            tags: [:type]
        end
      end,
      MyEmitterEvents
    )

    plugin = Module.concat([PromExpress.Metrics, "MyEmitterEvents"])
    [event_group] = plugin.event_metrics([])

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
end
