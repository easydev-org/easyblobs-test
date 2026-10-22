defmodule EasyblobsTestHello do
  @moduledoc "A real module the compiler must accept."

  @spec greet(String.t()) :: String.t()
  def greet(name), do: "hello #{name}"
end
