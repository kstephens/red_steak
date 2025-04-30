require 'red_steak'
require 'ostruct'
require 'fileutils' # FileUtils.mkdir_p
require 'pp'

RSpec.describe 'RedSteak::Machine guard spec' do

  # A test context for the StateMachine.
  class GuardTestContext
    attr_accessor :name, :m
    attr_accessor :_guard, :guard1, :guard2, :guard3
    attr_accessor :guard_called

    def initialize
      @guard_called = 0
    end

    [
     :event1,
     :event2,
     :event3,
     :event4,
    ].each do | meth |
      class_eval <<"RUBY", __FILE__, __LINE__
def #{meth}
  $stderr.puts "#{name} #{meth}()"
  @m.event! [ #{meth.inspect} ]
end
RUBY
    end

    def guard
      $stderr.puts "#{name} guard()"
      @guard_called += 1
      @_guard
    end

    def inspect
      "#{self.class} #{name} state=#{@m.state}"
    end

    def method_missing sel, *args
      $stderr.puts "#{name} #{sel}(#{args.inspect.gsub(/^\[|\]$/, '')})"
    end

    def sm
      @sm ||=
        RedSteak::Builder.new.build do
        statemachine :guard_test do
          initial :initial
          final :final

          state :initial

          transition :state1,
            :trigger => :event1,
            :guard => :guard1

          transition :state2,
            :trigger => :event1,
            :guard => :guard2

          state :state1
          transition :state2,
            :trigger => :event2,
            :guard => :guard3

          state :state2
          transition :state3,
            :trigger => :event3

          state :state3
          transition :final,
            :trigger => :event4

          state :final
        end
      end
    end
  end


  def render_graph sm, opts = { }
    opts[:dir] ||= File.expand_path(File.dirname(__FILE__) + '/../doc/example')
    FileUtils.mkdir_p(opts[:dir])

    opts[:name_prefix] = "red_steak-#{File.basename(__FILE__)}-"
    @graph_id ||= 0
    opts[:name_suffix] = "-%02d" % (@graph_id += 1)

    opts[:show_state_sequence] = true
    opts[:show_transition_sequence] = true
    opts[:highlight_state_history] = true
    opts[:highlight_transition_history] = true
    opts[:show_effect] = true
    opts[:show_guard] = true
    opts[:show_entry] = true
    opts[:show_exit] = true
    opts[:show_do] = true

    RedSteak::Dot.new.render_graph(sm, opts)
  rescue RedSteak::Error => err
    raise err unless err.to_s =~ /dot command failed/ # Old versions of dot might SEGV!
    # pp sm.history
  end


  ####################################################################


  attr_accessor :c, :m

  before(:each) do
    begin
      self.c = GuardTestContext.new
      c.name = "t"
      sm = c.sm
      self.m = sm.machine
      m.context = c

      c.m = m
      m.logger = lambda { | msg | $stderr.puts "  m #{msg}" } if ENV['TEST_VERBOSE']
      m.history = [ ]
      render_graph(m)

      m.start!
      render_graph(m)

    rescue Exception => err
      $stderr.puts "UNEXPECTED ERROR: #{err.inspect}"
      raise err
    end
  end

  it 'it will error if all guards return nil for multiple transitions.' do
    expect do
      expect(c.guard1).to eq(nil)
      expect(c.guard2).to eq(nil)

      c.event1
      m.run_events!
    end.to raise_error(RedSteak::Error::UnhandledEvent, "No transitions for event")
  end

  it 'it will error if all guards return false for multiple transitions.' do
    expect do
      c.guard1 = c.guard2 = false
      expect(c.guard1).to eq(false)
      expect(c.guard2).to eq(false)

      c.event1
      m.run_events!
    end.to raise_error(RedSteak::Error::UnhandledEvent, "No transitions for event")
  end

  it 'it will error if all guards return true for multiple transitions.' do
    expect do
      c.guard1 = c.guard2 = true
      expect(c.guard1).to eq(true)
      expect(c.guard2).to eq(true)

      c.event1
      m.run_events!
    end.to raise_error(RedSteak::Error::UnhandledEvent, "Too many transititons for event")
  end

  it 'it will not error if one and only one guard returns true' do
    lambda do
      c.guard1 = true
      expect(c.guard1).to eq(true)
      expect(c.guard2).to eq(nil)

      c.event1
      m.run_events!
      expect(m.state.name).to eq(:state1)
    end.call
  end

  it 'it will use #guard, by default.' do
    lambda do
      c.guard1 = true
      c.guard3 = true
      c._guard = true

      expect(c.guard1).to eq(true)
      expect(c.guard2).to eq(nil)
      expect(c.guard3).to eq(true)

      c.event1
      c.event2
      c.event3
      c.event4
      m.run_events!
      expect(c.guard_called).to eq(2)
      expect(m.state.name).to eq(:final)
    end.call
  end

end # describe
