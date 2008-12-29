# -*- ruby -*-

require 'red_steak'

describe RedSteak do

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
    
        state :a, :option_foo => :foo do
          transition :a, :name => 'foo'
          transition :a, :name => 'bar'
        end
        transition :a, :b, 
          :name => :a_to_b # ,
	  #:context => 
	  #:can_transition? => :can_issue_loan?
	  
	# state :q, :enter_state => :entering_q
        
        state :b do 
          transition :c
          transition :c, :name => 'c2'
        end
        
        state :c do
          transition :a
          transition :end
        end
        
        state :d do
          transition :a, :d
          transition :end
          statemachine do
            start_state :d1
            end_state :end
            
            state :d1 do
              transition :d2
              transition :end
            end
            state :d2 do
              transition :d1
              transition :end
            end
            state :d3 do
              transition :d1
            end
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

    sm.states.find{|x| x.name == :a}.options[:option_foo].should == :foo

    sm.validate.should == [ ]

    ssm = sm.states[:d].substatemachine
    ssm.should_not == nil
    ssm.start_state.name.should == :d1
    ssm.end_state.name.should == :end

  end


  # A test context for the Statemachine.
  class RedSteak::TestContext
    attr_accessor :enter_state, :exit_state, :before_transition, :after_transition
    attr_accessor :state_added, :transition_added
    attr_accessor :can_transition

    # This is the guard before
    # enter_state!, after_state!.
    # Must return true if the transition is 
    # allowed.
    def can_transition?(m, trans, *args)
      self.can_transition = trans.name

=begin
      $stderr.puts "  GUARD #{trans.inspect}"
      case trans.name
      when :'a_to_b'
        # false
        @guard_1 = false
      else
        true
      end
=end
    end

    def before_transition!(m, trans, *args)
      _log
      self.before_transition = trans.name
    end

    def exit_state!(m, state, *args)
      _log
      self.exit_state = state.name
    end

    def enter_state!(m, state, *args)
      _log
      self.enter_state = state.name

=begin
      do_some_stuff_here
      @guard_1 = true
      
      state.statemachine.transition_to! :next_state
=end
    end

    def after_transition!(m, trans, *args)
      _log
      self.after_transition = trans.name
    end


    # Statemachine change notifications.
    def transition_added!(m, trans, *args)
      _log
      self.transition_added = trans.name
    end

    def state_added!(m, state, *args)
      _log
      self.state_added = state.name
    end


    def _log
      # $stderr.puts "  CALLBACK: #{caller(1).first}"
    end
  end


  # Returns a Machine that can walk a Statemachine with context object.
  def machine_with_context sm = nil
    sm ||= statemachine

    x = sm.machine

    x.deep_history = x.history_enabled = true

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

    x.start!
    x.at_start?.should == true
    x.at_end?.should == false

    x.state.name.should == :a
    x.state.should === :a
    c.enter_state.should == :a
    c.exit_state.should == nil
    c.before_transition.should == nil
    c.after_transition.should == nil

    x.transition! "a_to_b"
    x.at_start?.should == false
    x.at_end?.should == false

    x.state.name.should == :b
    x.state.should === :b
    c.enter_state.should == :b
    c.exit_state.should == :a
    c.before_transition.should == :a_to_b
    c.after_transition.should == :a_to_b

    x.transition! :"b->c"
    x.state.name.should == :c
    x.at_start?.should == false
    x.at_end?.should == false

    x.transition! :"c->a"
    x.state.name.should == :a

    x.transition! "foo"
    x.state.name.should == :a

    x.transition! :bar
    x.state.name.should == :a

    x.transition! "foo"
    x.state.name.should == :a

    x.transition_to! :b
    x.state.name.should == :b

    x.transition! :'c2'
    x.state.name.should == :c

    x.transition_to! :end
    x.at_start?.should == false
    x.at_end?.should == true
    x.state.name.should == :end

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
     "end"
    ]

    x.history.map { |h| h[:transition].to_s }.should ==
    [
      '',
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

    # start transitions in substates.
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

    x.start!
    x.at_start?.should == true
    x.at_end?.should == false

    x.state.name.should == :a
    c.enter_state.should == :a
    c.exit_state.should == nil
    c.before_transition.should == nil
    c.after_transition.should == nil

    render_graph x, :show_history => true

    x.transition_to! :f
    x.state.name.should == :f

    x.transition_to! :end
    x.state.name.should == :end

    render_graph x, :show_history => true

  end

end

