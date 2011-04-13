# -*- ruby -*-

$: << File.dirname(__FILE__) + '../lib'

require 'red_steak'
require 'ostruct'
require 'fileutils' # FileUtils.mkdir_p
require 'pp'


describe 'RedSteak::Machine guard spec' do

  # A test context for the StateMachine.
  class GuardTestContext
    attr_accessor :name, :m
    attr_accessor :guard1, :guard2, :guard3

    def initialize
    end

    [
     :event1,
     :event2,
    ].each do | meth |
      class_eval <<"RUBY", __FILE__, __LINE__
def #{meth}
  $stderr.puts "#{name} #{meth}()"
  @m.event! [ #{meth.inspect} ]
end
RUBY
    end


    def inspect
      "#{self.class} #{name} state=#{@m.state.to_s}"
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
            :trigger => :event2

          state :state3
          transition :final

          state :final
        end
      end
    end
  end


  def render_graph sm, opts = { }
    opts[:dir] ||= File.expand_path(File.dirname(__FILE__) + '/../doc/example')
    FileUtils.mkdir_p(opts[:dir])

    opts[:name_prefix] = 'red_steak-'
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
      m.logger = lambda { | msg | $stderr.puts "  m #{msg}" }
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
    lambda do
      c.guard1.should == nil
      c.guard2.should == nil
      
      c.event1
      m.run_events!
    end.should raise_error(RedSteak::Error::UnhandledEvent, "Too many transititons for event")
  end

  it 'it will error if all guards return false for multiple transitions.' do
    lambda do
      c.guard1 = c.guard2 = false
      c.guard1.should == false
      c.guard2.should == false
      
      c.event1
      m.run_events!
    end.should raise_error(RedSteak::Error::UnhandledEvent, "No transitions for event")
  end

  it 'it will error if all guards return true for multiple transitions.' do
    lambda do
      c.guard1 = c.guard2 = true
      c.guard1.should == true
      c.guard2.should == true
      
      c.event1
      m.run_events!
    end.should raise_error(RedSteak::Error::UnhandledEvent, "Too many transititons for event")
  end

  it 'it will not error if one and only one guard returns true' do
    lambda do
      c.guard1 = true
      c.guard1.should == true
      c.guard2.should == nil
      
      c.event1
      m.run_events!
      m.state.name.should == :state2
    end.should_not raise_error(RedSteak::Error::UnhandledEvent, "something")
  end

end # describe


