defmodule PromExpress.CodegenTest do
  use ExUnit.Case

  alias PromExpress.Test.CompilationHelper

  test "generates a PromEx plugin module marked for discovery" do
    CompilationHelper.compile_and_get!(
      quote do
        defmodule MyEmitterForCodegen do
          use PromExpress.Emitter, root_event: :test, poll_rate: 1234
          require PromExpress

          polling_metric(:test_a, :last_value, description: "A")
          event_metric(:event_test, :counter, description: "E", tags: [:type])

          def poll_metrics(), do: %{test_a: 1}
          def fire(type), do: PromExpress.metric_event(:event_test, 1, %{type: type})
        end
      end,
      MyEmitterForCodegen
    )

    assert Code.ensure_loaded?(MyEmitterForCodegen)
    attrs = apply(MyEmitterForCodegen, :__info__, [:attributes])
    assert true in Keyword.get(attrs, :prom_ex_plugin, [])

    assert function_exported?(MyEmitterForCodegen, :polling_metrics, 1)
    assert function_exported?(MyEmitterForCodegen, :event_metrics, 1)
  end
end
