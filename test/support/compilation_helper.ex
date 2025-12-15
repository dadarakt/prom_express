defmodule PromExpress.Test.CompilationHelper do
  def compile_modules(quoted) do
    Code.compile_quoted(quoted)
    |> Enum.map(fn {mod, _bin} -> mod end)
  end

  def compile_and_get!(quoted, expected_module) when is_atom(expected_module) do
    mods = compile_modules(quoted)

    unless expected_module in mods do
      raise "Expected #{inspect(expected_module)} to be compiled, got: #{inspect(mods)}"
    end

    expected_module
  end
end
