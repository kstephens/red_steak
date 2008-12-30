# -*- ruby -*-

require 'red_steak'

describe RedSteak do

  # A test context for the Statemachine.
  class RedSteak::TestContext
    attr_accessor :_machine, :_args

    # Transition Behaviors:
    attr_accessor :_transition, :_guard, :_effect

    # State Behaviors:
    attr_accessor :_state, :_enter, :_exit, :_doActivity

    attr_accessor :_a_to_b

    # For debugging.
    attr_accessor :logger

    def clear!
      @_machine = 
        @_args =
        @_transition =
        @_guard =
        @_effect =
        @_state =
        @_enter =
        @_exit =
        @_doActivity =
        @_a_to_b =
        nil
    end


    # Called by Transition#guard?
    def guard(machine, trans, *args)
      @_machine = machine
      @_transition = trans
      @_guard = @_args = args
      _log
      nil # Ok
    end

    def a_to_b?(machine, trans, *args)
      @_machine = machine
      @_transition = trans
      @_guard = @_args = args
      @_a_to_b = args
      _log
      true
    end

    # Called by Transition#effect
    def effect(machine, trans, *args)
      @_machine = machine
      @_transition = trans
      @_effect = @_args = args
      _log
    end

    # Called by State#enter!
    def enter(machine, state, *args)
      @_machine = machine
      @_state = state
      @_enter = @_args = args
      _log
    end

    # Called by State#exit!
    def exit(machine, state, *args)
      @_machine = machine
      @_state = state
      @_exit = @_args = args
      _log
    end

    # Called by State#doActivity!
    def doActivity(machine, state, *args)
      @_machine = machine
      @_state = state
      @_doActivity = @_args = args
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


  # Returns the test Statemachine using the Builder.
  def statemachine
    # There can only one.
    return Thread.current[:statemachine] if Thread.current[:statemachine]

    b = RedSteak::Builder.new
    # breakpointer
    
    b.build do
      statemachine :test do
        start_state :a
        end_state :b
    
        state :a, :option_foo => :foo
        transition :a, :name => 'foo'
        transition :a, :name => 'bar'

        transition :a, :b, 
          :name => :a_to_b,
          :guard => :a_to_b?
	  
	# state :q, :enter_state => :entering_q
        
        state :b
        transition :c
        transition :c, :name => 'c2'
        
        state :c
        transition :a
        transition :end
        
        state :d
        transition :a, :d
        transition :end
        state :d do
          statemachine do
            start_state :d1
            end_state :end
            
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
          end
        end

        end_state :end
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

    sm.states.
      map{ | x | x.name }.
      sort { | a, b | a.to_s <=> b.to_s }.
      should == 
      [
       :a, :b, :c, :d, :end
      ].sort { | a, b | a.to_s <=> b.to_s }

    sm.transitions.
      map{ | x | x.name }.
      sort { | a, b | a.to_s <=> b.to_s }.
      should == 
      [
	:foo, :bar, :a_to_b, :'b->c', :c2, :'c->a', :'c->end', :'a->d', :'d->end'
      ].sort { | a, b | a.to_s <=> b.to_s }

    sm.start_state.name.should == :a
    sm.end_state.name.should == :end

    sm.states[:end].inspect.should == 
      "#<RedSteak::State test end>"

    sm.states[:d].substatemachine.states[:d1].inspect.should == 
      "#<RedSteak::State test::d d::d1>"

    e = sm.states[:end]
    e.should_not == nil
    e.transitions.to_a.map{|t| t.name}.should == [ :'c->end', :'d->end' ]
    e.targets.to_a.should == [ ]
    e.sources.to_a.map{|s| s.to_s}.should == [ 'c', 'd' ]

    sm.states.find{|x| x.name == :a}.options[:option_foo].should == :foo

    sm.validate.should == [ ]

    ssm = sm.states[:d].substatemachine
    ssm.should_not == nil
    ssm.start_state.name.should == :d1
    ssm.end_state.name.should == :end

  end


  # Returns a Machine that can walk a Statemachine with context object.
  def machine_with_context sm = nil
    sm ||= statemachine

    x = sm.machine

    x.history = [ ]

    if ENV['TEST_VERBOSE']
      x.logger = $stdout
    end
      
    x.context = RedSteak::TestContext.new
    # x.transitions[:'a->b'].context = SomeOther

    x
  end


  # Render graph.
  def render_graph x, opts = { }
    case x
    when RedSteak::Machine
      sm = x.statemachine
    when RedSteak::Statemachine
      sm = x
    end

    dir = opts[:dir] || File.expand_path(File.dirname(__FILE__) + '/../example')
    file = "#{dir}/red_steak-"
    opts[:name] ||= sm.name
    file += opts[:name].to_s
    file += '-history' if opts[:show_history]
    file += ".dot"
    File.open(file, 'w') do | fh |
      opts[:stream] = fh
      RedSteak::Dot.new(opts).render(x)
    end
    file_svg = "#{file}.svg"

    cmd = "dot -V"
    if system("#{cmd} >/dev/null 2>&1") == true
      cmd = "dot -Tsvg:cairo:cairo #{file.inspect} -o #{file_svg.inspect}"
      system(cmd).should == true
      $stdout.puts "View file://#{file_svg}"
    else
      $stderr.puts "Warning: #{cmd} failed"
    end
  end

  
  it 'should generate Dot output' do
    sm = statemachine
    render_graph sm
  end


  it 'should handle transitions' do
    x = machine_with_context
    c = x.context

    c.clear!

    #################################
    # Start
    #

    x.history.size.should == 0
    x.start!
    x.at_start?.should == true
    x.at_end?.should == false

    x.state.name.should == :a
    x.state.should === :a

    c._machine.should == x
    c._state.should == x.states[:a]
    c._transition.should == nil
    c._guard.should == nil
    c._effect.should == nil
    c._enter.should == [ ]
    c._exit.should == nil
    c._doActivity.should == [ ]
    x.history.size.should == 1

    #################################
    # Transition 1
    #

    c.clear!
    x.transition! "a_to_b", :arg
    x.at_start?.should == false
    x.at_end?.should == false

    x.state.name.should == :b
    x.state.should === :b

    c._machine.should == x
    c._transition.name.should == :a_to_b
    c._guard.should == [ :arg ]
    c._a_to_b.should == [ :arg ]
    c._effect.should == [ :arg ]
    c._state.name.should == :b
    c._enter.should == [ :arg ]
    c._exit.should == [ :arg ]
    c._doActivity.should == [ :arg ]
    x.history.size.should == 2

    #################################
    # Transition 2
    #

    c.clear!
    x.transition! :"b->c"
    x.state.name.should == :c
    x.at_start?.should == false
    x.at_end?.should == false
    x.history.size.should == 3

    c.clear!
    x.transition! :"c->a"
    x.state.name.should == :a
    x.history.size.should == 4

    x.transition! "foo"
    x.state.name.should == :a
    x.history.size.should == 5

    x.transition! :bar
    x.state.name.should == :a
    x.history.size.should == 6

    x.transition! "foo"
    x.state.name.should == :a
    x.history.size.should == 7

    x.transition_to! :b
    x.state.name.should == :b
    x.history.size.should == 8

    x.transition! :'c2'
    x.state.name.should == :c
    x.history.size.should == 9

    x.transition_to! :end
    x.at_start?.should == false
    x.at_end?.should == true
    x.state.name.should == :end
    x.history.size.should == 10

    x.history.map { |h| h[:previous_state].to_s }.should ==
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
    ]

    x.history.map { |h| h[:new_state].to_s }.should ==
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
     "end",
    ]

    x.history.map { |h| h[:transition].to_s }.should ==
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
      'c->end',
    ]

    render_graph x, :show_history => true
  end


  it 'should handle substatemachines' do
    x = machine_with_context

    x.start!
    x.state.name.should == :a
    x.at_start?.should == true
    x.at_end?.should == false
    x.state.substatemachine.should == nil

    x.transition_to! :d
    x.state.name.should == :d
    x.state.should === :d
    x.state.should === "d"

    # start transitions in substates of State :d.
    ssm = x.sub
    ssm.should_not == nil

    ssm.state.name.should == :d1
    ssm.state.should === :d1
    ssm.state.should === "d::d1"
    ssm.state.should === /^d::/
    ssm.state.should === x.states[:d]
    ssm.at_start?.should == true

    ssm.transition_to! :d2
    ssm.state.name.should == :d2
    ssm.at_end?.should == false

    ssm.transition_to! :d1
    ssm.state.name.should == :d1
    ssm.at_end?.should == false

    ssm.transition_to! :end
    ssm.state.name.should == :end
    ssm.at_end?.should == true

    x.at_end?.should == false

    x.transition_to! :end
    x.at_end?.should == true

    render_graph x, :name => "with-substates", :show_history => true
  end


  it 'should handle augmentation via builder' do
    sm = statemachine.copy
    sm.name = "#{sm.name}-augmented"

    a = sm.states[:a]
    a.should_not == nil
    a.targets.map{|s| s.name}.should == [ :a, :b, :d ]
    e = sm.states[:end]
    e.should_not == nil
    e.sources.map{|s| s.name}.should == [ :c, :d ]

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
    sm.states[:end].sources.map{|s| s.name}.should == [ :c, :d, :f ]

    ############################################

    x = machine_with_context(sm)
    c = x.context
 
    x.start! :foo, :bar
    x.at_start?.should == true
    x.at_end?.should == false

    x.state.name.should == :a
    c._machine.should == x
    c._state.name.should == :a
    c._enter.should == [ :foo, :bar ]
    c._exit.should == nil
 
    render_graph x, :show_history => true

    x.transition_to! :f
    x.state.name.should == :f

    x.transition_to! :end
    x.state.name.should == :end

    render_graph x, :show_history => true

  end


  it 'should handle substates' do
    sm = RedSteak::Statemachine.
    new(:name => :test2).
    build(:logger => nil && $stderr) do
      start_state 'a::a'
      end_state :end

      state :a do
        state :a          # same as "a::a"
        transition [ :b ] # same as "b"
        transition :c

        state :b          # same as "a:;b"
        transition [ :c ] # same as "c"
        transition :c

        state :c          # same as "a::c"
        transition "c"
      end

      state :b
      transition :c

      state :c 
      transition :end

      state :end
    end


    # $stderr.puts "transitions = #{sm.transitions.inspect}"
      
    sm.states[:a].substates.map{|s| s.to_s}.should == [ "a::a", "a::b", "a::c" ]
    sm.states["a::a"].superstate.should == sm.states["a"]

    sm.states["a::a"].targets.map{|s| s.to_s}.should == [ "b", "a::c" ]
    sm.states["a::b"].targets.map{|s| s.to_s}.should == [ "c", "a::c" ]
    sm.states["a::c"].targets.map{|s| s.to_s}.should == [ "c" ]

    sm.states[:c].sources.map{|s| s.to_s}.should == [ 'a::b', 'a::c', 'b' ]

    render_graph sm, :show_history => true
  end
  
end # describe


