# -*- ruby -*-

require 'red_steak'

describe RedSteak do

  # A test context for the Statemachine.
  class RedSteak::TestContext2
    attr_accessor :_logger

    attr_reader :history

    def initialize
      @history = [ ]
    end

    def a machine, *args
      @history << :a
      _log
      machine.transition_to! :b
    end

    def b machine, *args
      @history << :b
      _log
    end

    def c machine, *args
      @history << :c
      _log
      machine.transition_to! :d
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
        transition :a
        transition :d

        state :d, :do => :d
      end
    end
  end


  it 'should queue transition executions inside doActions in auto_run is enabled' do
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

    # This transition should invoke run!
    m.transition! :'b->c'
    m.state.name.should == :d

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
  

  it 'should not queue transition executions inside doActions in auto_run is disabled' do
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
  

end # describe


