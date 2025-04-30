require 'red_steak'

describe RedSteak do

  # A test context for the Statemachine.
  class RedSteak::TestContext2
    include RedSteak::Logging

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
      super(caller(1).first)
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
    # m.logger = $stderr if ENV['TEST_VERBOSE']
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    # m.context._logger = $stderr if ENV['TEST_VERBOSE']

    m.start!
    expect(m.state.name).to eq(:a)
    expect(m.transition_queue.size).to eq(1)

    m.run! :single
    expect(m.state.name).to eq(:b)
    expect(m.transition_queue.size).to eq(0)

    # Nothing pending so run! does nothing here.
    m.run!
    expect(m.state.name).to eq(:b)

    # This transition should invoke run!,
    # until at_end?
    m.transition! :'b->c'
    expect(m.state.name).to eq(:d)

    block_executed = false
    m.run! do
      block_executed = true
    end
    expect(block_executed).to eq(false)
    expect(m.state.name).to eq(:d)

    expect(m.at_end?).to eq(true)

    expect(m.context.history).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )

    expect(m.history.map { | h | h[:new_state].name }).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )
  end


  it 'should not queue transition executions inside doActions, if auto_run is disabled' do
    m = sm.machine
    m.auto_run = false
    # m.logger = $stderr if ENV['TEST_VERBOSE']
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    # m.context._logger = $stderr if ENV['TEST_VERBOSE']

    m.start!
    expect(m.state.name).to eq(:a)
    expect(m.transition_queue.size).to eq(1)

    m.run! :single
    expect(m.state.name).to eq(:b)
    expect(m.transition_queue.size).to eq(0)

    # Nothing queued.
    m.run!
    expect(m.state.name).to eq(:b)

    # auto_run is turned off, transition! should not auto run!
    m.transition! :'b->c'
    expect(m.state.name).to eq(:b)

    # Explicit run is required.
    m.run! :single
    expect(m.state.name).to eq(:c)

    m.run!
    expect(m.at_end?).to eq(true)

    expect(m.context.history).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )

    expect(m.history.map { | h | h[:new_state].name }).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )
  end


  it 'should executed pending Transition before run! and execute blocks until at_end or no pending Transitions' do
    m = sm.machine
    m.auto_run = false
    # m.logger = $stderr if ENV['TEST_VERBOSE']
    m.history = [ ]
    m.context = RedSteak::TestContext2.new
    m.context.do_trans = false

    m.start!
    expect(m.state.name).to eq(:a)
    expect(m.transition_queue.size).to eq(0)

    # this sequence should to nothing
    # because no transitions are valid.
    block_executed = false
    m.run! do | x |
      block_executed = true
      expect(x).to be(m)
      expect(m.transition_if_valid!).to eq(nil)
    end
    expect(block_executed).to eq(true)
    expect(m.state.name).to eq(:a)

    m.transition! :'a->b'
    expect(m.transition_queue.size).to eq(1)
    block_executed = false
    m.run!(:single) do | x |
      block_executed = true
    end
    expect(block_executed).to eq(false)
    expect(m.transition_queue.size).to eq(0)
    expect(m.state.name).to eq(:b)

    block_executed = false
    s = t = nil
    m.run! do | x |
      block_executed = true
      s = x.state
      t = m.transition_if_valid!
    end
    expect(block_executed).to eq(true)
    expect(m.transition_queue.size).to eq(0)
    expect(m.state.name).to eq(:d)
    expect(s.name).to eq(:c)
    expect(t.name).to eq(:"c->d")

    expect(m.at_end?).to eq(true)

    expect(m.context.history).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )

    expect(m.history.map { | h | h[:new_state].name }).to eq(
      [
       :a,
       :b,
       :c,
       :d,
      ]
    )
  end

end # describe
