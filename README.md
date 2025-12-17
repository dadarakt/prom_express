# PromExpress

**PromExpress** is a small DSL for defining and emitting [PromEx](https://hexdocs.pm/prom_ex) metrics with compile-time validation and minimal boilerplate.

It lets you declare polling and event-based metrics in one place and automatically generates a `PromEx.Plugin` implementation for discovery by PromEx.

The aim is not to replace the great `PromEx` library (all credit goes there) but just to provide a simpler (and opinionated) option for declaring metrics.

## Installation

Add `prom_express` to your dependencies:

```elixir
def deps do
  [
    {:prom_express, "~> 0.1.0"}
  ]
end
```

## Defining Metrics
Create a module and use PromExpress.Emitter.

### Event metrics

```elixir
defmodule MyApp.Metrics do
  use PromExpress.Emitter, root_event: :my_app

  event_metric :requests, :counter,
    description: "Number of requests",
    tags: [:status]
end
```

### Polling metrics

```elixir
defmodule MyApp.SystemMetrics do
  use PromExpress.Emitter, root_event: :my_app, poll_rate: 5_000

  polling_metric :memory, :last_value,
    description: "Memory usage"

  def poll_metrics do
    %{memory: :erlang.memory(:total)}
  end
end
```

If a module defines polling metrics, it must implement `poll_metrics/0`.
Missing implementations fail compilation.

## Emitting Metrics

### From the same module

```elixir
defmodule MyApp.Metrics do
  use PromExpress.Emitter
  
  event_metric :test, :last_value
  def handle_request(status) do
    PromExpress.metric_event(:requests, 1, %{status: status})
  end
end
```
The metric name is validated at compile time when given as a literal atom.

### From another module

```elixir
defmodule MyWorker do
  require PromExpress

  def record(status) do
    PromExpress.metric_event_in(MyApp.Metrics, :requests, 1, %{status: status})
  end
end
```

When both the module and metric name are literals, invalid metric names cause
compile-time errors.

## Generated PromEx Plugin Code
Each module using PromExpress.Emitter automatically becomes a PromEx.Plugin
and is marked for discovery by PromEx.

Generated functions include:
- `polling_metrics/1`
- `event_metrics/1`

You can choose to manually register the plugins with your application's `PromEx` module,
or use the `PromExpress.metric_plugins/0` helper to automatically retrieve all matching plugin modules.
```elixir
@impl true
def plugins do
[
  Plugins.Application,
  ...
] ++ PromExpress.metric_plugins()
end
```

## License
MIT
