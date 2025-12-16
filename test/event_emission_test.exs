defmodule PromExpress.EventEmissionTest do
  use ExUnit.Case, async: true

  test "metric_event emits the expected telemetry event and payload" do
    PromExpress.Test.CompilationHelper.compile_modules(
      quote do
        defmodule MyEmitterEmit do
          use PromExpress.Emitter, root_event: :prom_express

          event_metric(:event_test, :counter,
            description: "Count events",
            tags: [:type]
          )

          def fire(type), do: metric_event(:event_test, 1, %{type: type})
        end
      end
    )

    event_name = [:prom_express, :my_emitter_emit, :event_test]

    handler_id = "test-handler-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      event_name,
      &PromExpress.Test.TelemetryHandler.handle_event/4,
      self()
    )

    mod = :"Elixir.MyEmitterEmit"
    assert Code.ensure_loaded?(mod)
    assert function_exported?(mod, :fire, 1)

    apply(mod, :fire, [:push])

    assert_receive {:telemetry, ^event_name, %{value: 1}, %{type: :push}}, 500

    :telemetry.detach(handler_id)
  end
end
