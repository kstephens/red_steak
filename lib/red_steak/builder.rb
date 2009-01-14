
module RedSteak

  # DSL for building StateMachine objects.
  class Builder
    # The top-level StateMachine.
    attr_accessor :result

    # Logger
    attr_accessor :logger

    def initialize opts = EMPTY_HASH, &blk
      @context = { }
      @context_stack = { }
      @previous = { }
      @logger = nil
      @states = [ ]
      @transitions = [ ]

      opts.each do | k, v |
        s = "#{k}="
        if respond_to?(s)
          send(s, v) 
          opts.delete(k)
        end
      end

      build &blk if block_given?
    end


    # Begins building StateMachine by evaluating block.
    def build &blk
      raise ArgumentError, "expected block" unless block_given?
      instance_eval &blk
      @result
    end


    ##################################################################
    # DSL methods
    #

    # Creates a new StateMachine or augments an existing one.
    #
    # Create syntax:
    #
    #   sm = builder.build do 
    #     statemachine :my_statemachine do
    #       start_state :a
    #       end_state   :end
    #       state :a, :do => :a_behavior
    #       state :b
    #       state :c do
    #         state :substate_1
    #         state :substate_2
    #         transition "b", :substate1
    #         transition :substate1, :substate2
    #         transition :substate2, "end"
    #       end
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
      when StateMachine
        sm = name
        name = sm.name
      else
        name = name.to_sym unless Symbol === name
        
        opts[:name] = name
        sm = StateMachine.new opts
      end

      # Save the result.
      @result ||= sm

      # Attach state to substate machine.
      if superstate
        superstate.submachine = sm 
        sm.superstate = superstate
      end

      _with_context(:state, nil) do
        _with_context(:initial, nil) do 
          _with_context(:final, nil) do
            _with_context(:namespace, sm) do
              _with_context(:statemachine, sm) do 
                instance_eval &blk if blk
                
                # Set start, end states.
                sm.start_state = _find_state(@context[:initial]) if @context[:initial]
                sm.end_state   = _find_state(@context[:final])   if @context[:final]
                
              end # statemachine

              # Outermost statemachine?
              if @context[:statemachine] == nil
                _log { "\n\nCreating transitions:" }
                # Create transitions.
                @transitions.each do | t |
                  _create_transition! t
                end
                @transitions.clear
              end
            end # namespace
          end # end_state
        end # start_state
      end # state
      
      sm
    end

    
    # Defines a submachine inside a State.
    def submachine opts = { }, &blk
      raise ArgumentError, "submachine only valid inside a state" unless State === @current
      raise ArgumentError, "submachine only valid once inside a state" if @current.submachine
      name = @current.name
      statemachine name, opts, &blk
    end


    # Defines the initial state.
    def initial name, opts = { }
      opts[:name] = name
      @context[:initial] = opts
      self
    end


    # Defines the final state.
    def final name, opts = { }
      opts[:name] = name
      @context[:final] = opts
      self
    end


    # Definse a Pseudostate.
    def pseudostate kind, name, opts = { }
      raise NotImplemented
    end


    # Creates a state.
    #
    # States have a name and three behaviors:
    #
    #   :entry - action performed when state is entered.
    #   :do - action peformed during state.
    #   :exit - action performed when state is exited.
    #
    # :do is an alias for :doActivity.
    #
    # Syntax:
    #
    #   state :name
    #   state :name, :option_1 => 'foo'
    #   state :name do
    #     submachine do 
    #       state :substate_1, :do => :method_on_context, :exit => :method1
    #       state :substate_2, :entry => :method2
    #     end
    #   end
    #
    #
    def state name, opts = { }, &blk
      raise ArgumentError, "states must be defined within a statemachine or submachine" unless StateMachine === @current

      opts[:name] = name

      if x = opts.delete(:do)
        opts[:doActivity] = x
      end

      s = _find_state opts

      _with_context :namespace, s do 
        _with_context :state, s do 
          if blk
            instance_eval &blk 
          end
        end
      end

      s
    end


    # Creates a transition between two states.
    #
    # If only one state name is given, the previously defined state is the source state.
    #
    # Syntax:
    #
    # Creates a transition named :'a->b' from state :a to state :b.
    #
    #   state :a
    #   state :b
    #   transition :a, :b
    #
    # Creates a transition named :a_to_b from state :a to state :b.
    #
    #   state :a
    #   # source :a is implied on next line.
    #   # state :b is implied if not declared elsewhere
    #   transition :b, :name => :a_to_b  
    #
    def transition *args, &blk
      if Hash === args.last
        opts = args.pop
      else
        opts = { }
      end
      
      case args.size
      when 1 # target
        opts[:source] = @previous[:state] ||
        (raise ArgumentError, "no previous state has been defined")
        opts[:target] = args.first
      when 2 # source, target
        opts[:source], opts[:target] = *args
      else
        raise ArgumentError, "expected (target) or (source, target)"
      end
      
      raise ArgumentError, "source state not given" unless opts[:source]
      raise ArgumentError, "target state not given" unless opts[:target]
      
      opts[:statemachine] = @context[:statemachine]
      @transitions << {
        :block => blk,
        :owner => _owner,
        :opts => opts,
      }
      
      self
    end
    

    private

    def _with_context name, val
      current_save = @current
 
      (@context_stack[name] ||= [ ]).push(@context[name])
      
      @current = 
        @context[name] = 
        val
      
      if name == :namespace
        (@context[:namespaces] ||= [ ]).push(val)
      end

      yield
      
    ensure
      @previous[name] = val

      @current = current_save
      
      @context[name] = @context_stack[name].pop

      if name == :namespace
        (@context[:namespaces] ||= [ ]).pop
      end
    end
   

    # Determine what object should own
    # a new State if one is created.
    def _owner
      @context[:statemachine] ||
        (raise Exception, "statemachine is unknown")
    end


    # Locates a state by name or creates a new object.
    def _find_state opts, param = EMPTY_HASH
      create = param[:create] != false
      owner = param[:owner]
      cls = param[:class] || State

      _log { "_find_state #{opts.inspect}, #{param.inspect}" }

      # Parse opts.
      name = nil
      case opts
      when String, Symbol, Array
        name = opts
        opts = { }
      when Hash
        name = opts[:name]
      when State
        return opts
      else
        raise ArgumentError, "invalid opts, given #{opts.inspect}"
      end

      # Split Strings on "::"
      name = name.split(SEP) if String === name
 
      # Determine owner.
      owner ||= _owner unless owner
      raise Exception, "Cannot determine owner for new State #{name.inspect}" unless owner

      # Attempt to locate existing State object.
      case name
      when nil
        raise ArgumentError, "State name not specified" unless name

      # If Array is given, start at root StateMachine.
      when Array
        path = name
        name = path.pop.to_sym
        owner = @result
        _log { "  looking for State #{name.inspect} in path #{path.inspect}" }
        path.each do | e |
          break unless owner
          owner = _find_state(e.to_sym, :owner => owner)
        end
        raise ArgumentError, "Cannot locate State #{name.inspect} in #{owner.inspect}" unless owner

        # Find existing State by name in owner.
        state = owner.state[name]

      # Search up namespaces till Object is found is found.
      else
        state = nil

        # Try owner first.
        if owner
          _log { "  looking for State #{name.inspect} directly in owner = #{owner.inspect}:" }
          state = owner.state[name]
        end
      end


      _log { "  state = #{state.inspect} in #{owner.inspect}" }

=begin
      $stderr.puts "  owner = #{owner.inspect}"
      $stderr.puts "caller = #{caller(0)[0 .. 4] * "\n  "}"
      $stderr.puts "state = #{state.inspect}"
=end

      # Create a new one, if requested.
      if create && ! state
        opts[:name] = name
        _log { "  creating #{cls} #{opts.inspect} for #{owner.inspect}" }
        state = cls.new opts
        owner.add_state! state
        _log { "  created #{state.inspect} for #{owner.inspect}" }
      else
        if state
          state.options = opts
        end
      end
      
      state
    end


    # Called after all States have been created.
    def _create_transition! t
      owner = t[:owner]
      blk = t[:block]
      opts = t[:opts]

      _log { "\n\n_create_transition! #{t.inspect}" }

      opts[:source] = _find_state opts[:source], :owner => owner
      opts[:target] = _find_state opts[:target], :owner => owner

      _log { "  #{opts.inspect}" }
       
      t = _find_transition opts

      _with_context :transition, t do        
        instance_eval &blk if blk
      end
    end


    # Locates a transition by name or creates a new object.
    def _find_transition opts
      raise ArgumentError, "opts expected Hash" unless Hash === opts

      opts[:source] = _find_state opts[:source]
      opts[:target] = _find_state opts[:target]
      opts[:name] ||= "#{opts[:source].to_s}->#{opts[:target].to_s}".to_sym

      t = opts[:statemachine].transitions.find do | x |
        opts[:name] == x.name
      end
      
      unless t
        # opts[:statemachine] ||= @context[:statemachine]
        t = Transition.new opts
        opts[:statemachine].add_transition! t
      else
        if t
          opts.delete(:name)
          t.options = opts
        end
      end
      
      t
    end


    def _log msg = nil
      case @logger
      when ::IO
        msg ||= yield
        msg = "#{self.class} #{msg}"
        @logger.puts msg
      end
    end

  end # class

end # module


###############################################################################
# EOF
