$: << 'lib'
require 'red_steak'

$sm = RedSteak::StateMachine.build do
  statemachine :example1 do
    initial :a
    final :c

    state :a
    transition :b
    transition :a

    state :b
    transition :c

    state :c
  end
end

class Example1Context
  def exit *args
    puts "   #{self.class} exit #{args.inspect.gsub(/^\[|\]$/, '')}"
    self
  end
  def method_missing sel, *args
    puts "   #{self.class} #{sel} #{args.inspect.gsub(/^\[|\]$/, '')}"
    self
  end
  def respond_to? sel
    true
  end
end

$c = Example1Context.new

$m = $sm.machine
$m.auto_run = :single
$m.context = $c
$m.history = [ ]
$m.start!

