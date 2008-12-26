
module RedSteak

  # DSL for building state machines.
  class Builder
    # The top-level statemachine.
    attr_accessor :result

    def initialize &blk
      @context = { }
      @context_stack = { }
      build &blk if block_given?
    end

    def build &blk
      instance_eval &blk
      result
    end


    ##################################################################
    # DSL methods
    #

    # Creates a new statemachine or augments an existing one.
    #
    # Create syntax:
    #
    #   sm = builder.build do 
    #     statemachine :my_statemachine do
    #       start_state :a
    #       end_state   :end
    #       state :a
    #       state :b
    #       state :end
    #       transition :a, :b
    #       transition :b, :end
    #     end
    #   end
    #
    # Augmenting syntax:
    #
    #   sm.builder do 
    #     state :c
    #     transition :a, :c
    #     transition :c, :end
    #   end
    #
    def statemachine name = nil, opts = { }, &blk
      # Create a sub state machine?
      superstate = @context[:state]
      if superstate
        name = superstate.name
      end
      raise(ArgumentError, 'invalid name') unless name

      case name
      when Statemachine
        sm = name
        name = sm.name
      else
        name = name.to_sym unless Symbol === name
        
        opts[:name] = name
        sm = Statemachine.new opts
      end

      # Save the result.
      @result ||= sm

      # Attach state to substate machine.
      if superstate
        superstate.substatemachine = sm 
        sm.superstate = superstate
      end

      _with_context(:state, nil) do
        _with_context(:start_state, nil) do 
          _with_context(:end_state, nil) do
            _with_context(:statemachine, sm) do 
              if blk
                instance_eval &blk 
                
                # Do this at the end.
                sm.start_state = _find_state(@context[:start_state]) if @context[:start_state]
                sm.end_state   = _find_state(@context[:end_state])   if @context[:end_state]

#=begin
                # Associate substates with their superstate
                # prototypes.
                if superstate
                  sm.states.each do | s |
                    s.superstate = superstate
                  end
                end
#=end
              end
            end
          end
        end
      end
    end


    # Defines the start state.
    def start_state state
      @context[:start_state] = state
    end


    # Defines the end state.
    def end_state state
      @context[:end_state] = state
    end


    # Creates a state.
    def state name, opts = { }, &blk
      opts[:name] = name
      s = _find_state opts
      _with_context :state, s do 
        instance_eval &blk if blk
      end
    end


    # Creates a transition between two states.
    #
    # Syntax:
    #
    #   state :a do 
    #     transition :b
    #   end
    #   state :b
    #
    # Creates a transition named :'a->b' from state :a to state :b.
    #
    #   state :a
    #   state :b
    #   transition :a, :b
    #
    # Creates a transition name :'a->b' from state :a to state :b.
    #
    #   state :a do
    #     transition :b, :name => :a_to_b
    #   end
    #   state b:
    #
    # Creates a transition named :a_to_b from state :a to state :b.
    def transition *args, &blk
      if Hash === args.last
        opts = args.pop
      else
        opts = { }
      end

      case args.size
      when 1 # target
        opts[:source] = @context[:state]
        opts[:target] = args.first
      when 2 # source, target
        opts[:source], opts[:target] = *args
      else
        raise(ArgumentError)
      end

      raise ArgumentError unless opts[:source]
      raise ArgumentError unless opts[:target]
      
      opts[:source] = _find_state opts[:source]
      opts[:target]   = _find_state opts[:target]

      t = _find_transition opts
      _with_context :transition, t do
        instance_eval &blk if blk
      end
    end


    # Dispatches method to the current context.
    def method_missing sel, *args, &blk
      if @current
        return @current.send(sel, *args, &blk)
      end
      super
    end


    private

    def _with_context name, val
      current_save = @current
 
      (@context_stack[name] ||= [ ]).push(@context[name])
      
      @current = 
        @context[name] = 
        val
      
      yield
      
    ensure
      @current = current_save
      
      @context[name] = @context_stack[name].pop
    end
   

    # Locates a state by name or creates a new object.
    def _find_state opts, create = true
      $stderr.puts "_find_state #{opts.inspect}, #{create.inspect} from #{caller(1).first}" if ! create

      raise ArgumentError, "opts" unless opts

      name = nil
      case opts
      when String, Symbol
        name = opts.to_sym
        opts = { }
      when Hash
        name = opts[:name].to_sym
      when State
        return opts
      else
        raise ArgumentError, "given #{opts.inspect}"
      end

      raise ArgumentError, "name" unless name

      s = @context[:statemachine].states.find do | x | 
        name === x.name
      end

      if create && ! s
        opts[:name] = name
        opts[:statemachine] = @context[:statemachine]
        s = State.new opts
        @context[:statemachine].add_state! s
      else
        if s 
          s.options = opts
        end
      end

      s
    end


    # Locates a transition by name or creates a new object.
    def _find_transition opts
      raise ArgumentError, "opts expected Hash" unless Hash === opts

      opts[:source] = _find_state opts[:source]
      opts[:target]   = _find_state opts[:target]
      opts[:name] ||= "#{opts[:source].name}->#{opts[:target].name}".to_sym

      t = @context[:statemachine].transitions.find do | x |
        opts[:name] == x.name
      end
      
      unless t
        opts[:statemachine] = @context[:statemachine]
        t = Transition.new opts
        @context[:statemachine].add_transition! t
      else
        if t
          opts.delete(:name)
          t.options = opts
        end
      end
      
      t
    end
    
  end # class

end # module


###############################################################################
# EOF
