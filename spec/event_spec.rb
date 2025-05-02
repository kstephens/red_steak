require 'red_steak'
require 'red_steak/example/telephone'
require 'red_steak/example/render'
require 'ostruct'
require 'fileutils' # FileUtils.mkdir_p
require 'pp'

RSpec.describe 'RedSteak::Machine#event!' do
  attr_accessor :t

  it 'transitions using transition_if_valid!' do
  begin
    self.t = RedSteak::Example::Telephone.new
    t.name = "test"
    sm = t.sm
    m = sm.machine
    m.context = t
    t.m = m
    m.logger = lambda { | msg | $stderr.puts "  m #{msg}" } if ENV['TEST_VERBOSE']
    m.history = [ ]

    render = RedSteak::Example::Render.new(context: self.t, machine: m)
    render.render_graph!

    m.start!
    render.render_graph!

    events =
      [
       [ :lift_receiver,  ],
       [ :dial_digit, "5" ],
       [ :dial_digit, "5" ],
       [ :dial_digit, "5" ],
       [ :dial_digit, "9" ],
       [ :dial_digit, "8" ],
       [ :dial_digit, "7" ],
       [ :dial_digit, "6" ],
       [ :connected, ],
       [ :callee_answers, ],
       # [ :dial_digit, "#" ],
       [ :caller_hangs_up, ],
       [ :terminate, ],
      ]

    until m.at_end?
      # t.log :context, t.inspect
      event = events.shift
      raise "out of events" unless events
      t.send(*event)
      m.run_events!
      render.render_graph!
    end
  rescue Exception => err
    $stderr.puts "UNEXPECTED ERROR: #{err.inspect}"
    raise err
  end
  end
end
