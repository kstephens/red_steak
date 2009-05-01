# -*- ruby -*-

require 'red_steak'

describe RedSteak do

  # A test context for the StateMachine.
  class RedSteak::TestContext
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


    # Called by Transition#guard?
    def guard(machine, trans, *args)
      @_machine = machine
      @_transition = trans
      @_guard << (@_args = args)
      _log
      nil # Ok
    end

    # Special Guard.
    def a_to_b?(machine, trans, *args)
      guard(machine, trans, *args)
      @_a_to_b = args
      true
    end

    def e_f_guard_true(machine, trans, *args)
      true
    end

    def e_f_guard_false(machine, trans, *args)
      false
    end

    # Called by Transition#effect
    def effect(machine, trans, *args)
      @_machine = machine
      @_transition = trans
      @_effect << (@_args = args)
      _log
    end

    # Called by State#entry!
    def entry(machine, state, *args)
      @_machine = machine
      @_state = state
      @_args = args
      @_entry << [ state.to_s, *args ]
      _log
    end

    # Called by State#exit!
    def exit(machine, state, *args)
      @_machine = machine
      @_state = state
      @_args = args
      @_exit << [ state.to_s, *args ]
      _log
    end

    # Called by State#doActivity!
    def doActivity(machine, state, *args)
      @_machine = machine
      @_state = state
      @_args = args
      @_doActivity << [ state.to_s, *args ]
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
	  
	# state :q, :entry_state => :entrying_q
        
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

=begin
    $stderr.puts "sm = #{sm.inspect}"
    $stderr.puts "transitions = #{sm.transitions.inspect}"
    $stderr.puts "states = #{sm.states.inspect}"
=end

    Thread.current[:statemachine] = sm

    sm
  end
  

  it 'should build a statemachine' do
    sm = statemachine

    sm.inspect.should == "#<RedSteak::StateMachine test>"

    sm.states.
      map{ | s | s.name }.
      sort { | a, b | a.to_s <=> b.to_s }.
      should == 
      [
       :a, :b, :c, :d, :e, :end, :f
      ].sort { | a, b | a.to_s <=> b.to_s }

    sm.transitions.
      map{ | t | t.name }.
      sort { | a, b | a.to_s <=> b.to_s }.
      should == 
      [
        :bar, :a_to_b, :'b->c', :c2, :'c->a', :'c->end', :'a->d', :'d->end', :e1, :"f->d", :"f->end", :foo, :tran_e_1, :tran_e_2
      ].sort { | a, b | a.to_s <=> b.to_s }

    sm.start_state.name.should == :a
    sm.end_state.name.should == :end

    # Check State.options[] and State#[].
    a = sm.states[:a]
    a.should_not == nil
    a.options[:option_foo].should_not == nil
    a[:option_foo].should == a.options[:option_foo]

    b = sm.states[:b]
    b.should_not == nil
    b.options[:option_foo].should == nil
    b[:option_foo].should == b.options[:option_foo]

    sm.states[:end].inspect.should == 
      "#<RedSteak::State test end>"

    sm.states[:d].submachine.states[:d1].inspect.should == 
      "#<RedSteak::State test::d d::d1>"

    e = sm.states[:end]
    e.should_not == nil
    e.transitions.to_a.map{|t| t.name}.should == [ :'c->end', :'f->end', :'d->end', :'d::end->end' ]
    e.targets.to_a.should == [ ]
    e.sources.to_a.map{|s| s.to_s}.should == [ 'c', 'f', 'd', 'd::end' ]

    sm.states[:a].options[:option_foo].should == :foo

    sm.validate.should == [ ]

    ssm = sm.states[:d].submachine
    ssm.should_not == nil
    ssm.start_state.name.should == :d1
    ssm.end_state.name.should == :end

    ssm.state[:d1].stateMachine.should == ssm
    ssm.state[:d1].superstate.should == sm.state[:d]

    sm.state[:d].ancestors.map{|s| s.to_s}.should == [ "d" ]
    ssm.state[:d1].ancestors.map{|s| s.to_s}.should == [ "d::d1", "d" ]
  end


  # Returns a Machine that can walk a StateMachine with context object.
  def machine_with_context sm = nil
    sm ||= statemachine

    m = sm.machine

    m.history = [ ]

    if ENV['TEST_VERBOSE']
      m.logger = $stdout
    end
      
    m.context = RedSteak::TestContext.new

    m
  end


  # Render graph.
  def render_graph sm, opts = { }
    opts[:dir] ||= File.expand_path(File.dirname(__FILE__) + '/../example')
    opts[:name_prefix] = 'red_steak-'
    RedSteak::Dot.new.render_graph(sm, opts)
  end

  
  it 'should generate Dot output' do
    sm = statemachine
    render_graph sm
  end


  it 'should handle transitions' do
    m = machine_with_context
    m.auto_run = true
    c = m.context

    c.clear!
    # c._logger = $stderr

    #################################
    # Start
    #

    m.history.size.should == 0
    m.start!
    m.at_start?.should == true
    m.at_end?.should == false

    m.state.name.should == :a
    m.state.should === :a

    c._machine.should == m
    c._state.should == m.stateMachine.states[:a]
    c._transition.should == nil
    c._guard.should == [ ]
    c._effect.should == [ ]
    c._entry.should == [ [ "a" ] ]
    c._exit.should == [ ]
    c._doActivity.should == [ [ "a" ] ]
    m.history.size.should == 1

    m.guard?.should == true

    #################################
    # Transition 1
    #

    c.clear!
    m.transition! "a_to_b", :arg1
    m.at_start?.should == false
    m.at_end?.should == false

    m.state.name.should == :b
    m.state.should === :b

    c._machine.should == m
    c._transition.name.should == :a_to_b
    c._guard.should == [ [ :arg1 ] ]
    c._a_to_b.should == [ :arg1 ]
    c._effect.should == [ [ :arg1 ] ]
    c._state.name.should == :b
    c._entry.should == [ [ "b", :arg1 ] ]
    c._exit.should == [ [ "a", :arg1 ] ]
    c._doActivity.should == [ [ "b", :arg1 ] ]
    m.history.size.should == 2

    #################################
    # Transition 2
    #

    c.clear!
    m.transition! :"b->c"
    m.state.name.should == :c
    m.at_start?.should == false
    m.at_end?.should == false
    m.history.size.should == 3

    c.clear!
    m.transition! :"c->a"
    m.state.name.should == :a
    m.history.size.should == 4
    m.state.outgoing.map{|t| t.name}.should == [ :foo, :bar, :a_to_b, :'a->d' ] 

    m.transition! "foo"
    m.state.name.should == :a
    m.history.size.should == 5
    m.state.outgoing.map{|t| t.name}.should == [ :foo, :bar, :a_to_b, :"a->d" ]

    m.transition! :bar
    m.state.name.should == :a
    m.history.size.should == 6
    m.state.outgoing.map{|t| t.name}.should == [ :foo, :bar, :a_to_b, :"a->d" ]

    m.transition! "foo"
    m.state.name.should == :a
    m.history.size.should == 7

    m.transition_to! :b
    m.state.name.should == :b
    m.history.size.should == 8

    m.transition! :'c2'
    m.state.name.should == :c
    m.history.size.should == 9

    m.transition! :e1
    m.state.name.should == :e
    m.history.size.should == 10

    m.transition_to_next_state!
    m.state.name.should == :f
    m.history.size.should == 11

    m.transition_to! :end
    m.at_start?.should == false
    m.at_end?.should == true
    m.guard?.should == false
    m.state.name.should == :end
    m.history.size.should == 12

    m.transition_to_next_state!(false).should == nil
    lambda { m.transition_to_next_state!(true)}.should raise_error(RedSteak::Error::UnknownTransition)

    m.history.map { |h| h[:previous_state].to_s }.should ==
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

    m.history.map { |h| h[:new_state].to_s }.should ==
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

    m.history.map { |h| h[:transition].to_s }.should ==
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

    render_graph m, :show_history => true
  end


  it 'should handle submachines' do
    m = machine_with_context
    m.auto_run = true
    sm = m.stateMachine

    m.start!
    m.state.name.should == :a
    m.state.submachine.should == nil

    m.transition_to! :d
    m.state.name.should == :d1
    m.state.should === :d1
    m.state.should === sm.states[:d]
    # m.state.submachine.should_not == nil

    # start transitions in substates of State :d.
=begin
    ssm = m.sub
    ssm.should_not == nil
=end
    ssm = m

    ssm.state.name.should == :d1
    ssm.state.should === :d1
    ssm.state.should === "d::d1"
    ssm.state.should === /^d::/
    ssm.state.should === ssm.state.superstate
    # ssm.at_start?.should == true

    ssm.transition_to! "d::d2"
    ssm.state.name.should == :d2
    ssm.at_end?.should == false

    ssm.transition_to! "d::d1"
    ssm.state.name.should == :d1
    ssm.at_end?.should == false

    ssm.transition_to! "d::end"
    ssm.state.name.should == :end
    # ssm.at_end?.should == true

    m.at_end?.should == false

    m.transition_to! :end
    m.at_end?.should == true

    render_graph m, :name => "with-substates", :show_history => true
  end


  it 'should handle augmentation via builder' do
    sm = statemachine.copy
    sm.name = "#{sm.name}-augmented"

    a = sm.states[:a]
    a.should_not == nil
    a.targets.map{|s| s.name}.should == [ :a, :b, :d ]
    e = sm.states[:end]
    e.should_not == nil
    e.sources.map{|s| s.name}.should == [ :c, :f, :d, :end ]

    # Add state :f and transitions from :a and to :end.
    sm.builder do 
      state :f
      transition :a, :f
      transition :f, :end
    end

    render_graph sm

    a.object_id.should == sm.states[:a].object_id
    e.object_id.should == sm.states[:end].object_id

    sm.states[:a].targets.map{|s| s.name}.should == [ :a, :b, :d, :f ]
    sm.states[:end].sources.map{|s| s.name}.should == [ :c, :f, :d, :end ]

    ############################################

    m = machine_with_context(sm)
    m.auto_run = true
    c = m.context
 
    m.start! :foo, :bar
    m.at_start?.should == true
    m.at_end?.should == false

    m.state.name.should == :a
    c._machine.should == m
    c._state.name.should == :a
    c._entry.should == [ [ "a", :foo, :bar ] ]
    c._exit.should == [ ]
 
    render_graph m, :show_history => true

    m.transition_to! :f
    m.state.name.should == :f

    m.transition_to! :end
    m.state.name.should == :end
    
    render_graph m, :show_history => true
    
  end


  it 'should handle transitions across substates and states' do
    logger = nil && $stderr
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

    render_graph sm

    # $stderr.puts "transitions = #{sm.transitions.inspect}"
    sm.state[:a].should == sm.state['a']
    sm.state[:b].should == sm.state['b']
    sm.state[:c].should == sm.state['c']


    sm.state[:a].source.map{|s| s.to_s}.should == [ "b::a" ]
    sm.state[:a].target.map{|s| s.to_s}.should == [ ]
    
    sm.state[:a].state.map{|s| s.to_s}.should == [ "a::a", "a::b", "a::c" ]
    sm.state["a::a"].superstate.should == sm.states["a"]
    sm.state["a::a"].should === sm.states["a"]

    sm.state["a::a"].target.map{|s| s.to_s}.should == [ "b", "a::c", "c" ]
    sm.state["a::a"].source.map{|s| s.to_s}.should == [ ]
  
    sm.state["a::b"].target.map{|s| s.to_s}.should == [ "c", "a::c" ]
    sm.state["a::b"].source.map{|s| s.to_s}.should == [ "b::b" ]

    sm.state["a::c"].target.map{|s| s.to_s}.should == [ "c" ]
    sm.state["a::c"].source.map{|s| s.to_s}.should == [ "a::a", "a::b" ]

    sm.state[:b].state.map{|s| s.to_s}.should == [ "b::a", "b::b" ]
    sm.state[:b].source.map{|s| s.to_s}.should == [ 'a::a' ]
    sm.state[:b].target.map{|s| s.to_s}.should == [ 'c' ]

    sm.state[:c].state.map{|s| s.to_s}.should == [ ]
    sm.state[:c].source.map{|s| s.to_s}.should == ["a::a", "a::b", "a::c", "b", "b::a"]

    m = machine_with_context(sm)
    m.auto_run = true
    c = m.context
    m.logger = $stderr

    c.clear!
    m.start!
    c._exit.should == [ ]
    c._entry.should == [ [ "a" ], [ "a::a" ] ]

    c.clear!
    m.transition_to! "b"
    c._exit.should == [["a::a"], ["a"]]
    c._entry.should == [ [ "b" ], [ "b::a" ] ]

    c.clear!
    m.transition_to! "b::b"
    c._exit.should == [["b::a"]]
    c._entry.should == [["b::b"]]

    c.clear!
    m.transition_to! "a::b"
    c._exit.should == [["b::b"], ["b"]]
    c._entry.should == [["a"], ["a::b"]] 

    c.clear!
    m.transition_to! "c"
    c._exit.should == [["a::b"], ["a"]]
    c._entry.should == [["c"]]

    render_graph m, :show_history => true

    svg_data = RedSteak::Dot.new.render_graph_svg_data(m, :show_history => true)
    # $stderr.puts svg_data
    svg_data.should =~ /\A<\?xml/
    svg_data.should =~ /<svg /
    svg_data.should =~ /<\/svg>/

    svg_data = RedSteak::Dot.new.render_graph_svg_data(m, :show_history => true, :xml_header => false)
    # $stderr.puts svg_data
    svg_data.should_not =~ /\A<\?xml/
    svg_data.should =~ /\A<svg /
    svg_data.should =~ /<\/svg>/
  end
  
end # describe


