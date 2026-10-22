require_relative 'lib/easyblobs_test_hello'

unless EasyblobsTestHello.greet('easyblobs') == 'hello easyblobs'
  raise 'bad greeting'
end

puts EasyblobsTestHello.greet('easyblobs')
