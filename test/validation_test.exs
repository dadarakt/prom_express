defmodule PromExpress.ValidationTest do
  use ExUnit.Case, async: true

  test "emitting an undefined event metric fails at compile time" do
    assert_raise ArgumentError, ~r/Unknown event metric/, fn ->
      PromExpress.Test.CompilationHelper.compile_modules(
        quote do
          defmodule MyEmitterInvalid do
            use PromExpress.Emitter, root_event: :prom_express
            require PromExpress

            event_metric(:known, :counter, description: "Known")

            def bad(), do: PromExpress.metric_event(:unknown, 1)
          end
        end
      )
    end
  end

  test "not implementing poll_metrics/0 when defining a polling_metric fails at compile time" do
    assert_raise CompileError, ~r/does not implement poll_metrics/, fn ->
      PromExpress.Test.CompilationHelper.compile_modules(
        quote do
          defmodule MissingPollingFunction do
            use PromExpress.Emitter, root_event: :prom_express

            polling_metric(:test, :sum)
          end
        end
      )
    end
  end
end
