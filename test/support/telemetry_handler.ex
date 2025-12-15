defmodule PromExpress.Test.TelemetryHandler do
  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end
end
