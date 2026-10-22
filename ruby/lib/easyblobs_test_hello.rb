# frozen_string_literal: true

# A real module the gem toolchain must load.
module EasyblobsTestHello
  module_function

  def greet(name)
    "hello #{name}"
  end
end
