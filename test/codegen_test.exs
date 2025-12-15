defmodule PromExpress.CodegenTest do
  use ExUnit.Case

  alias PromExpress.Test.CompilationHelper

  test "generates a PromEx plugin module marked for discovery" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterForCodegen do
          use PromExpress.Emitter, root_event: :pet_ai, poll_rate: 1234
          require PromExpress

          polling_metric :test_a, :last_value, description: "A"
          event_metric   :event_test, :counter, description: "E", tags: [:type]

          def poll_metrics(), do: %{test_a: 1}
          def fire(type), do: PromExpress.metric_event(:event_test, 1, %{type: type})
        end
      end,
      MyEmitterForCodegen
    )

    plugin = Module.concat([PromExpress.Metrics, "MyEmitterForCodegenMetrics"])
    assert Code.ensure_loaded?(plugin)

    attrs = plugin.__info__(:attributes)
    assert true in Keyword.get(attrs, :prom_ex_plugin, [])

    assert function_exported?(plugin, :polling_metrics, 1)
    assert function_exported?(plugin, :event_metrics, 1)
  end
end
