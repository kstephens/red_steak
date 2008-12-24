
require 'red_steak'

describe RedSteak do
  def statemachine
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
        transition :a, :b, :name => :a_to_b
        
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

    sm.states.find{|x| x.name == :a}._options[:option_foo].should == :foo

    sm.validate.should == [ ]
  end


  class RedSteak::TestContext
    attr_accessor :enter_state, :exit_state, :before_transition, :after_transition

    def enter_state!(state, *args)
      _log
      self.enter_state = state.name
    end

    def exit_state!(state, *args)
      _log
      self.exit_state = state.name
    end

    def before_transition!(trans, *args)
      _log
      self.before_transition = trans.name
    end

    def after_transition!(trans, *args)
      _log
      self.after_transition = trans.name
    end

    def _log
      # $stderr.puts "  CALLBACK: #{caller(1).first}"
    end
  end


  def statemachine_with_context
    sm = statemachine

    context = Object.new

    x = sm.dup
    if ENV['TEST_VERBOSE']
      x.logger = $stdout
    end
      
    x.context = RedSteak::TestContext.new

    x
  end


  def to_dot sm, opts = { }
    dir = opts[:dir] || File.expand_path(File.dirname(__FILE__) + '/../example')
    file = "#{dir}/red_steak-"
    opts[:name] ||= sm.name
    file += opts[:name].to_s
    file += '-history' if opts[:show_history]
    file += ".dot"
    File.open(file, 'w') do | fh |
      sm.to_dot fh, opts
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
    to_dot sm
  end


  it 'should handle transitions' do
    x = statemachine_with_context
    x.deep_history = history_enabled = true
    c = x.context

    x.start!
    x.state.name.should == :a
    c.enter_state.should == :a
    c.exit_state.should == nil
    c.before_transition.should == nil
    c.after_transition.should == nil
    x.at_start?.should == true
    x.at_end?.should == false

    x.transition! "a_to_b"
    x.state.name.should == :b
    c.enter_state.should == :b
    c.exit_state.should == :a
    c.before_transition.should == :a_to_b
    c.after_transition.should == :a_to_b
    x.at_start?.should == false
    x.at_end?.should == false

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

    x.transition_to! :b
    x.state.name.should == :b

    x.transition! :'c2'
    x.state.name.should == :c

    x.transition_to! :end
    x.state.name.should == :end
    x.at_start?.should == false
    x.at_end?.should == true

    x.history.size.should == 8
    x.history.map { |h| h[:transition].name }.should ==
    [
      :a_to_b, 
      :'b->c',
      :'c->a',
      :foo,
      :bar,
      :a_to_b,
      :c2,
      :'c->end'
    ]

    to_dot x, :show_history => true
  end


  it 'should handle substatemachines' do
    x = statemachine_with_context
    x.deep_history = history_enabled = true

    x.start!
    x.state.name.should == :a
    x.at_start?.should == true
    x.at_end?.should == false
    x.state.substatemachine.should == nil

    x.transition_to! :d
    x.state.name.should == :d

    # start transitions in substates.
    ssm = x.state.substatemachine
    ssm.should_not == nil
    ssm.state.name.should == :d1
    ssm.at_start?.should == true

    x.state.transition_to! :d2
    ssm.state.name.should == :d2
    ssm.at_end?.should == false

    x.state.transition_to! :d1
    ssm.state.name.should == :d1
    ssm.at_end?.should == false

    x.state.transition_to! :end
    ssm.state.name.should == :end
    ssm.at_end?.should == true

    x.at_end?.should == false

    x.transition_to! :end
    x.at_end?.should == true

    to_dot x, :name => "with-substates", :show_history => true
  end


  it 'should handle augmentation via builder' do
    x = statemachine_with_context
    x.name = "#{x.name}-augmented"
    x.builder do 
      state :f
      transition :a, :f
      transition :f, :end
    end

    c = x.context

    x.start!
    x.state.name.should == :a
    c.enter_state.should == :a
    c.exit_state.should == nil
    c.before_transition.should == nil
    c.after_transition.should == nil
    x.at_start?.should == true
    x.at_end?.should == false

    x.transition_to! :f
    x.state.name.should == :f

    x.transition_to! :end
    x.state.name.should == :end

    to_dot x

  end

end

