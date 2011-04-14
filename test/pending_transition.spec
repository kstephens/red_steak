# -*- ruby -*-

require 'red_steak'

describe RedSteak do

  # A test context for the Statemachine.
  class RedSteak::TestContext2
    attr_accessor :_logger

    attr_reader :history

    attr_accessor :do_trans

    def initialize
      @history = [ ]
      @do_trans = true
    end

    def a machine, *args
      @history << :a
      _log
      machine.transition_to! :b if @do_trans
    end

    def b machine, *args
      @history << :b
      _log
    end

    def c machine, *args
      @history << :c
      _log
      machine.transition_to! :d if @do_trans
    end

    def c_to_a? *args
      @do_trans
    end

    def c_to_d? *args
      true
    end

    def d machine, *args
      @history << :d
      _log
    end

    def _log
      case @_logger
      when IO
        @_logger.puts "  #{self.class}: #{caller(1).first}"
      end
      self
    end
  end


  def sm
    @sm ||=
      RedSteak::StateMachine.build do 
      statemachine :test2 do
        initial :a
        final :d
    
        state :a, :do => :a
        transition :a, :name => 'foo'
        transition :a, :name => 'bar'
        transition :b

        state :b, :do => :b
        transition :c
        
        state :c, :do => :c
        transition :a, :guard => :c_to_a?
        transition :d, :guard => :c_to_d?

        state :d, :do => :d
      end
    end
  end


  it 'should queue transition executions inside doActions, if auto_run is enabled' do
    m = sm.machine
    m.auto_run = true
    # m.logger = $stderr
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    # m.context._logger = $stderr

    m.start!
    m.state.name.should == :a
    m.transition_queue.size.should == 1

    m.run! :single
    m.state.name.should == :b
    m.transition_queue.size.should == 0

    # Nothing pending so run! does nothing here.
    m.run!
    m.state.name.should == :b

    # This transition should invoke run!,
    # until at_end?
    m.transition! :'b->c'
    m.state.name.should == :d

    block_executed = false
    m.run! do
      block_executed = true
    end
    block_executed.should == false
    m.state.name.should == :d

    m.at_end?.should == true

    m.context.history.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]

    m.history.map { | h | h[:new_state].name }.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]
  end
  

  it 'should not queue transition executions inside doActions, if auto_run is disabled' do
    m = sm.machine
    m.auto_run = false
    # m.logger = $stderr
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    # m.context._logger = $stderr

    m.start!
    m.state.name.should == :a
    m.transition_queue.size.should == 1

    m.run! :single
    m.state.name.should == :b
    m.transition_queue.size.should == 0

    # Nothing queued.
    m.run! 
    m.state.name.should == :b

    # auto_run is turned off, transition! should not auto run!
    m.transition! :'b->c'
    m.state.name.should == :b

    # Explicit run is required.
    m.run! :single
    m.state.name.should == :c

    m.run! 
    m.at_end?.should == true

    m.context.history.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]

    m.history.map { | h | h[:new_state].name }.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]
  end
  

  it 'should executed pending Transition before run! and execute blocks until at_end or no pending Transitions' do
    m = sm.machine
    m.auto_run = false
    # m.logger = $stderr
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    m.context.do_trans = false

    m.start!
    m.state.name.should == :a
    m.transition_queue.size.should == 0

    # this sequence should to nothing
    # because no transitions are valid.
    block_executed = false
    m.run! do | x |
      block_executed = true
      x.should == m
      m.transition_if_valid!.should == nil
    end
    block_executed.should == true
    m.state.name.should == :a

    m.transition! :'a->b'
    m.transition_queue.size.should == 1
    block_executed = false
    m.run!(:single) do | x |
      block_executed = true
    end
    block_executed.should == false
    m.transition_queue.size.should == 0
    m.state.name.should == :b

    block_executed = false
    s = t = nil
    m.run! do | x |
      block_executed = true
      s = x.state
      t = m.transition_if_valid!
    end
    block_executed.should == true
    m.transition_queue.size.should == 0
    m.state.name.should == :d
    s.name.should == :c
    t.name.should == :"c->d"

    m.at_end?.should == true

    m.context.history.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]

    m.history.map { | h | h[:new_state].name }.should ==
      [
       :a,
       :b,
       :c,
       :d,
      ]
  end
 
end # describe


