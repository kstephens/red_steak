require 'red_steak'
require 'red_steak/example/render'
require 'fileutils' # FileUtils.mkdir_p

RSpec.describe RedSteak do
  # A test context for the StateMachine.
  class RedSteak::TestContext
    include RedSteak::Logging

    attr_accessor :_machine, :_args

    # Transition Behaviors:
    attr_accessor :_transition, :_guard, :_effect

    # State Behaviors:
    attr_accessor :_state, :_entry, :_exit, :_doActivity

    attr_accessor :_a_to_b

    # For debugging.
    attr_accessor :_logger

    def initialize
      clear!
    end

    def clear!
      @_machine =
        @_args =
        @_transition =
        @_a_to_b =
        nil
      @_guard = [ ]
      @_effect = [ ]
      @_state = [ ]
      @_entry = [ ]
      @_exit = [ ]
      @_doActivity = [ ]
    end

    def capture_machine!
      action = RedSteak::Action.current or raise
      @_machine = action.machine
      @_transition = action.transition if action.transition
      @_state = action.state if action.state
      @_event = action.event if action.event
    end

    # Called by Transition#guard?
    def guard *args
      capture_machine!
      @_guard << (@_args = args)
      _log
      true # Ok
    end

    # Special Guard.
    def a_to_b?(*args)
      guard(*args)
      @_a_to_b = args
      true
    end

    def e_f_guard_true(*args)
      true
    end

    def e_f_guard_false(*args)
      false
    end

    # Called by Transition#effect
    def effect(*args)
      capture_machine!
      @_effect << (@_args = args)
      _log
    end

    # Called by State#entry!
    def entry(*args)
      capture_machine!
      @_args = args
      @_entry << [ @_state.to_s, *args ]
      _log
    end

    # Called by State#exit!
    def exit(*args)
      capture_machine!
      @_args = args
      @_exit << [ @_state.to_s, *args ]
      _log
    end

    # Called by State#doActivity!
    def doActivity(*args)
      capture_machine!
      @_args = args
      @_doActivity << [ @_state.to_s, *args ]
      _log
    end

    def _log
      super(caller(1).first)
      self
    end
  end


  # Returns the test StateMachine using the Builder.
  def statemachine
    # There can only one.
    return Thread.current[:statemachine] if Thread.current[:statemachine]

    b = RedSteak::Builder.new(:logger => false && $stderr)
    # breakpointer

    b.build do
      statemachine :test, :logger => false && $stderr do
        initial :a
        final :end

        state :a, :option_foo => :foo
        transition :a, :name => 'foo'
        transition :a, :name => 'bar'

        transition :a, :b,
          :name => :a_to_b,
          :guard => :a_to_b?

	# state :q, :entry_state => :entering_q

        state :b
        transition :c
        transition :c, :name => 'c2'

        state :c
        transition :a
        transition :c, :e, :name => :e1
        transition :end

        state :e
        transition :e, :f, :name => :tran_e_1, :guard => :e_f_guard_true
        transition :e, :f, :name => :tran_e_2, :guard => :e_f_guard_false

        state :f
        transition :f, :d
        transition :f, :end

        state :d
        transition :a, :d
        transition :end
        state :d do
          statemachine do
            initial :d1
            final :end

            state :d1
            transition :d2
            transition :end

            state :d2
            transition :d1
            transition :end

            state :d3
            transition :d1
            transition :d2, :d3

            state :end
            transition "end"
          end
        end
      end
    end

    sm = b.result

    Thread.current[:statemachine] = sm

    sm
  end


  it 'should build a statemachine' do
    sm = statemachine

    expect(sm.inspect).to eq("#<RedSteak::StateMachine test>")
    expect(sm.rootNamespace).to be(sm)

    expect(
      sm.states.
      map{ | s | s.name }.
      sort { | a, b | a.to_s <=> b.to_s }
    ).to eq(
      [
       :a, :b, :c, :d, :e, :end, :f
      ].sort { | a, b | a.to_s <=> b.to_s }
    )

    expect(
      sm.transitions.
      map{ | t | t.name }.
      sort { | a, b | a.to_s <=> b.to_s }
    ).to eq(
      [
        :bar, :a_to_b, :'b->c', :c2, :'c->a', :'c->end', :'a->d', :'d->end', :e1, :"f->d", :"f->end", :foo, :tran_e_1, :tran_e_2
      ].sort { | a, b | a.to_s <=> b.to_s }
    )

    expect(sm.start_state.name).to eq(:a)
    expect(sm.end_state.name).to eq(:end)

    # Check State.options[] and State#[].
    a = sm.states[:a]
    expect(a).to_not eq(nil)
    expect(a.options[:option_foo]).to_not eq(nil)
    expect(a[:option_foo]).to eq(a.options[:option_foo])

    b = sm.states[:b]
    expect(b).to_not eq(nil)
    expect(b.options[:option_foo]).to eq(nil)
    expect(b[:option_foo]).to eq(b.options[:option_foo])

    expect(sm.states[:end].inspect).to eq("#<RedSteak::State test end>")

    d = sm.states[:d]
    expect(d.submachine).to_not eq(nil)
    expect(d.submachine.rootNamespace).to be(sm)
    expect(d.submachine.superstatemachine).to be(sm)
    expect(d.submachine.rootStateMachine).to be(sm)

    d_d1 = d.submachine.states[:d1]
    expect(d_d1.inspect).to eq("#<RedSteak::State test::d d::d1>")
    expect(d.is_a_superstate_of?(d_d1)).to eq(true)
    expect(d_d1.is_a_superstate_of?(d)).to eq(false)
    expect(d_d1.is_a_substate_of?(d)).to eq(true)
    expect(d.is_a_substate_of?(d_d1)).to eq(false)
    expect(d.isSubmachineState).to eq(true)
    expect(d.is_submachine_state?).to eq(true)

    expect(d.namespace.class).to be(RedSteak::StateMachine)
    expect(d.namespace.name).to eq(:test)
    expect(d.namespace.root_namespace).to be(sm)

    expect(d_d1.namespace.class).to be(RedSteak::StateMachine)
    expect(d_d1.namespace).to be(d.submachine)
    expect(d_d1.namespace.name).to eq(:d)
    expect(d_d1.namespace.root_namespace).to be(sm)

    e = sm.states[:end]
    expect(e).to_not eq(nil)
    expect(e.transitions.to_a.map{|t| t.name}).to eq([ :'c->end', :'f->end', :'d->end', :'d::end->end' ])
    expect(e.targets.to_a).to eq([ ])
    expect(e.sources.to_a.map{|s| s.to_s}).to eq([ 'c', 'f', 'd', 'd::end' ])

    expect(sm.states[:a].options[:option_foo]).to eq(:foo)

    expect(sm.validate).to eq([ ])

    ssm = sm.states[:d].submachine
    expect(ssm).to_not eq(nil)
    expect(ssm.start_state.name).to eq(:d1)
    expect(ssm.end_state.name).to eq(:end)

    expect(ssm.state[:d1].stateMachine).to be(ssm)
    expect(ssm.state[:d1].superstate).to be(sm.state[:d])

    expect(sm.state[:d].ancestors.map{|s| s.to_s}).to eq([ "d" ])
    expect(ssm.state[:d1].ancestors.map{|s| s.to_s}).to eq([ "d::d1", "d" ])
  end


  # Returns a Machine that can walk a StateMachine with context object.
  def machine_with_context sm = nil
    sm ||= statemachine
    m = sm.machine
    m.history = [ ]
    m.logger = $stdout if ENV['TEST_VERBOSE']
    m.context = RedSteak::TestContext.new
    m
  end

  # Render graph.
  def render_graph! m, opts = { }
    opts = opts.dup
    opts[:highlight_state_history] = true
    opts[:highlight_transition_history] = true
    RedSteak::Example::Render.new(machine: m)
  end

  it 'should generate Dot output' do
    sm = statemachine
    render_graph! sm.machine
  end

  it 'should handle transitions' do
    m = machine_with_context
    m.auto_run = true
    c = m.context

    a = m.statemachine.states[:a]
    b = m.statemachine.states[:b]

    c.clear!
    # c._logger = $stderr if ENV['TEST_VERBOSE']

    #################################
    # Start
    #

    expect(m.history.size).to eq(0)
    m.start!
    expect(m.at_start?).to eq(true)
    expect(m.at_end?).to eq(false)

    expect(m.state.name).to eq(:a)
    expect(m.state === :a).to eq(true)
    expect(m.state).to be(a)

    expect(c._machine).to be(m)
    expect(c._state).to be(m.stateMachine.states[:a])
    expect(c._transition).to eq(nil)
    expect(c._guard).to eq([ ])
    expect(c._effect).to eq([ ])
    expect(c._entry).to eq([ [ "a" ] ])
    expect(c._exit).to eq([ ])
    expect(c._doActivity).to eq([ [ "a" ] ])
    expect(m.history.size).to eq(1)

    expect(m.guard?).to eq(true)

    #################################
    # Transition 1
    #

    c.clear!
    m.transition! "a_to_b", [:arg1]
    expect(m.at_start?).to eq(false)
    expect(m.at_end?).to eq(false)

    expect(m.state.name).to eq(:b)
    expect(m.state === :b).to eq(true)
    expect(m.state).to be(b)

    expect(c._machine).to be(m)
    expect(c._transition.name).to eq(:a_to_b)
    expect(c._guard).to eq([ [ :arg1 ] ])
    expect(c._a_to_b).to eq([ :arg1 ])
    expect(c._effect).to eq([ [ :arg1 ] ])
    expect(c._state.name).to eq(:b)
    expect(c._entry).to eq([ [ "b", :arg1 ] ])
    expect(c._exit).to eq([ [ "a", :arg1 ] ])
    expect(c._doActivity).to eq([ [ "b", :arg1 ] ])
    expect(m.history.size).to eq(2)
    expect(c._transition.to_uml_s).to eq("'a_to_b' [:a_to_b?]")

    #################################
    # Transition 2
    #

    c.clear!
    m.transition! :"b->c"
    expect(m.state.name).to eq(:c)
    expect(m.at_start?).to eq(false)
    expect(m.at_end?).to eq(false)
    expect(m.history.size).to eq(3)

    c.clear!
    m.transition! :"c->a"
    expect(m.state.name).to eq(:a)
    expect(m.history.size).to eq(4)
    expect(m.state.outgoing.map{|t| t.name}).to eq([ :foo, :bar, :a_to_b, :'a->d' ])

    m.transition! "foo"
    expect(m.state.name).to eq(:a)
    expect(m.history.size).to eq(5)
    expect(m.state.outgoing.map{|t| t.name}).to eq([ :foo, :bar, :a_to_b, :"a->d" ])

    m.transition! :bar
    expect(m.state.name).to eq(:a)
    expect(m.history.size).to eq(6)
    expect(m.state.outgoing.map{|t| t.name}).to eq([ :foo, :bar, :a_to_b, :"a->d" ])

    m.transition! "foo"
    expect(m.state.name).to eq(:a)
    expect(m.history.size).to eq(7)

    m.transition_to! :b
    expect(m.state.name).to eq(:b)
    expect(m.history.size).to eq(8)

    m.transition! :'c2'
    expect(m.state.name).to eq(:c)
    expect(m.history.size).to eq(9)

    m.transition! :e1
    expect(m.state.name).to eq(:e)
    expect(m.history.size).to eq(10)

    m.transition_to_next_state!
    expect(m.state.name).to eq(:f)
    expect(m.history.size).to eq(11)

    m.transition_to! :end
    expect(m.at_start?).to eq(false)
    expect(m.at_end?).to eq(true)
    expect(m.guard?).to eq(false)
    expect(m.state.name).to eq(:end)
    expect(m.history.size).to eq(12)

    expect(m.transition_to_next_state!(false)).to eq(nil)
    expect { m.transition_to_next_state!(true) }.to raise_error(RedSteak::Error::NoTransitions)
    begin
      m.transition_to_next_state!(true)
    rescue Object => err
      expect((RedSteak::Error === err)).to eq(true)
      # pp err.inspect
      # pp err.options
      expect(err.class).to be(RedSteak::Error::NoTransitions)
      expect(err.machine).to be(m)
      expect(err.message).to eq("transition_to_next_state!")
      expect(err.transitions).to eq(nil)
      expect(err.state).to be(m.state)
      expect(err.event).to be(nil)
    end

    expect(m.history.map { |h| h[:previous_state].to_s }).to eq(
    [
     "", # nil.to_s
     "a",
     "b",
     "c",
     "a",
     "a",
     "a",
     "a",
     "b",
     "c",
     "e",
     "f",
    ]
    )

    expect(m.history.map { |h| h[:new_state].to_s }).to eq(
    [
     "a",
     "b",
     "c",
     "a",
     "a",
     "a",
     "a",
     "b",
     "c",
     "e",
     "f",
     "end",
    ]
    )

    expect(m.history.map { |h| h[:transition].to_s }).to eq(
    [
      '', # nil.to_s
      'a_to_b',
      'b->c',
      'c->a',
      'foo',
      'bar',
      'foo',
      'a_to_b',
      'c2',
      'e1',
      'tran_e_1',
      'f->end',
    ]
    )

    render_graph! m, :show_history => true
  end


  it 'should handle #to_state.' do
    m = machine_with_context
    sm = m.stateMachine

    s = sm.state[:a]
    expect(s).to_not eq(nil)
    expect(m.to_state(s)).to be(s)
    expect(m.to_state(:a)).to be(s)
    expect(m.to_state("a")).to be(s)

    s = sm.state[:d].submachine.state[:d1]
    expect(s).to_not eq(nil)
    expect(m.to_state(s)).to be(s)
    expect(m.to_state("d::d1")).to be(s)
    expect(m.to_state(:"d::d1")).to eq(nil)
  end

  it 'should handle #to_transition' do
    m = machine_with_context
    sm = m.stateMachine

    t = sm.transition[:'a_to_b']
    expect(t).to_not eq(nil)
    expect(m.to_transition(t)).to be(t)
    expect(m.to_transition('a_to_b')).to be(t)
    expect(m.to_transition(:'a_to_b')).to be(t)

    t = sm.state[:d].submachine.transition[:'d::d1->d::d2']
    expect(t).to_not eq(nil)
    expect(m.to_transition(t)).to be(t)
  end

  it 'should handle #to_transition for namespaced transitions.' do
    pending "named_array.rb falsely recognizes :: separators imbedded in transitions names."
    m = machine_with_context
    sm = m.stateMachine

    t = sm.state[:d].submachine.transition[:'d::d1->d::d2']
    expect(t).to_not eq(nil)
    expect(m.to_transition(t)).to be(t)
    expect(m.to_transition("d::d1->d::d2")).to be(t)
    expect(m.to_transition(:"d::d1->d::d2")).to eq(nil)

    expect(m.to_transition("d::d1->d2")).to eq(nil)
  end

  it 'should handle submachines' do
    m = machine_with_context
    m.auto_run = true
    sm = m.stateMachine

    m.start!
    expect(m.state.name).to eq(:a)
    expect(m.state.submachine).to eq(nil)
    expect(m.state_is_active?(nil)).to eq(false)
    expect(m.state_is_active?(sm.states[:a])).to eq(true)

    m.transition_to! :d
    expect(m.state.name).to eq(:d1)
    expect(m.state === :d1).to eq(true)
    d = sm.states[:d]
    expect(m.state === d).to eq(true)
    d_d1 = d.submachine.states[:d1]
    expect(m.state_is_active?(d)).to eq(true)
    expect(m.state_is_active?(d_d1)).to eq(true)
    expect(m.state_is_active?(nil)).to eq(false)
    expect(m.state_is_active?(sm.states[:a])).to eq(false)

    # start transitions in substates of State :d.
=begin
    ssm = m.sub
    expect(ssm).to_not eq(nil)
=end
    ssm = m

    expect(ssm.state.name).to eq(:d1)
    expect(ssm.state === :d1).to eq(true)
    expect(ssm.state === "d::d1").to eq(true)
    expect(ssm.state === /^d::/).to eq(true)
    expect(ssm.state === ssm.state.superstate).to eq(true)
    # expect(ssm.at_start?).to eq(true)

    ssm.transition_to! "d::d2"
    expect(ssm.state.name).to eq(:d2)
    expect(ssm.at_end?).to eq(false)

    ssm.transition_to! "d::d1"
    expect(ssm.state.name).to eq(:d1)
    expect(ssm.at_end?).to eq(false)

    ssm.transition_to! "d::end"
    expect(ssm.state.name).to eq(:end)
    # expect(ssm.at_end?).to eq(true)

    expect(m.at_end?).to eq(false)

    m.transition_to! :end
    expect(m.at_end?).to eq(true)

    render_graph! m, :name => "with-substates", :show_history => true
  end


  it 'should handle augmentation via builder' do
    sm = statemachine.copy
    sm.name = "#{sm.name}-augmented"

    a = sm.states[:a]
    expect(a).to_not eq(nil)
    expect(a.targets.map{|s| s.name}).to eq([ :a, :b, :d ])
    e = sm.states[:end]
    expect(e).to_not eq(nil)
    expect(e.sources.map{|s| s.name}).to eq([ :c, :f, :d, :end ])

    # Add state :f and transitions from :a and to :end.
    sm.builder do
      state :f
      transition :a, :f
      transition :f, :end
    end

    render_graph! sm.machine

    expect(a.object_id).to eq(sm.states[:a].object_id)
    expect(e.object_id).to eq(sm.states[:end].object_id)

    expect(sm.states[:a].targets.map{|s| s.name}).to eq([ :a, :b, :d, :f ])
    expect(sm.states[:end].sources.map{|s| s.name}).to eq([ :c, :f, :d, :end ])

    ############################################

    m = machine_with_context(sm)
    m.auto_run = true
    c = m.context

    m.start! [:foo, :bar]
    expect(m.at_start?).to eq(true)
    expect(m.at_end?).to eq(false)

    expect(m.state.name).to eq(:a)
    expect(c._machine).to be(m)
    expect(c._state.name).to eq(:a)
    expect(c._entry).to eq([ [ "a", :foo, :bar ] ])
    expect(c._exit).to eq([ ])

    render_graph! m, :show_history => true

    m.transition_to! :f
    expect(m.state.name).to eq(:f)

    m.transition_to! :end
    expect(m.state.name).to eq(:end)

    render_graph! m, :show_history => true
  end


  it 'should handle transitions across substates and states' do
    logger = $stderr if ENV['TEST_VERBOSE']
    sm = RedSteak::StateMachine.
      new(:name => :test2, :logger => logger).
      build(:logger => logger) do
      initial :a
      final :end

      state :a do
        submachine do
          initial :a

          state :a # same as "a::a"
          transition [ :b ] # same as "b"
          transition :c
          transition "c"

          state :b          # same as "a:;b"
          transition [ :c ] # same as "c"
          transition :c

          state :c          # same as "a::c"
          transition "c"
        end
      end

      state :b
      transition :c
      state :b do
        submachine do
          initial :a

          state :a
          transition "a"
          transition "c"
          transition :b

          state :b
          transition "a::b"
        end
      end

      state :c
      transition :end
    end

    render_graph! sm.machine

    expect(sm.state[:a]).to be(sm.state['a'])
    expect(sm.state[:b]).to be(sm.state['b'])
    expect(sm.state[:c]).to be(sm.state['c'])

    expect(sm.state[:a].source.map{|s| s.to_s}).to eq([ "b::a" ])
    expect(sm.state[:a].target.map{|s| s.to_s}).to eq([ ])

    expect(sm.state[:a].state.map{|s| s.to_s}).to eq([ "a::a", "a::b", "a::c" ])
    expect(sm.state["a::a"].superstate).to be(sm.states["a"])
    expect(sm.state["a::a"] === sm.states["a"]).to eq(true)

    expect(sm.state["a::a"].target.map{|s| s.to_s}).to eq([ "b", "a::c", "c" ])
    expect(sm.state["a::a"].source.map{|s| s.to_s}).to eq([ ])

    expect(sm.state["a::b"].target.map{|s| s.to_s}).to eq([ "c", "a::c" ])
    expect(sm.state["a::b"].source.map{|s| s.to_s}).to eq([ "b::b" ])

    expect(sm.state["a::c"].target.map{|s| s.to_s}).to eq([ "c" ])
    expect(sm.state["a::c"].source.map{|s| s.to_s}).to eq([ "a::a", "a::b" ])

    expect(sm.state[:b].state.map{|s| s.to_s}).to eq([ "b::a", "b::b" ])
    expect(sm.state[:b].source.map{|s| s.to_s}).to eq([ 'a::a' ])
    expect(sm.state[:b].target.map{|s| s.to_s}).to eq([ 'c' ])

    expect(sm.state[:c].state.map{|s| s.to_s}).to eq([ ])
    expect(sm.state[:c].source.map{|s| s.to_s}).to eq(["a::a", "a::b", "a::c", "b", "b::a"])

    m = machine_with_context(sm)
    m.auto_run = true
    c = m.context
    m.logger = $stderr if ENV['TEST_VERBOSE']

    c.clear!
    m.start!
    expect(c._exit).to eq([ ])
    expect(c._entry).to eq([ [ "a" ], [ "a::a" ] ])

    c.clear!
    m.transition_to! "b"
    expect(c._exit).to eq([["a::a"], ["a"]])
    expect(c._entry).to eq([ [ "b" ], [ "b::a" ] ])

    c.clear!
    m.transition_to! "b::b"
    expect(c._exit).to eq([["b::a"]])
    expect(c._entry).to eq([["b::b"]])

    c.clear!
    m.transition_to! "a::b"
    expect(c._exit).to eq([["b::b"], ["b"]])
    expect(c._entry).to eq([["a"], ["a::b"]])

    c.clear!
    m.transition_to! "c"
    expect(c._exit).to eq([["a::b"], ["a"]])
    expect(c._entry).to eq([["c"]])

    render_graph! m, :show_history => true

    svg_data = RedSteak::Dot.new.render_graph_svg_data(m, :show_history => true)
    expect(svg_data).to match(/\A<\?xml/)
    expect(svg_data).to match(/<svg /)
    expect(svg_data).to match(%r{</svg>})

    svg_data = RedSteak::Dot.new.render_graph_svg_data(m, :show_history => true, :xml_header => false)
    expect(svg_data).to_not match(/\A<\?xml/)
    expect(svg_data).to match(/\A<svg /)
    expect(svg_data).to match(%r{</svg>})
  end
end
