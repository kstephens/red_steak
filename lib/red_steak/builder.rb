
module RedSteak

  # DSL for building state machines.
  class Builder
    # The top-level statemachine.
    attr_accessor :result

    # Logger
    attr_accessor :logger

    def initialize opts = EMPTY_HASH, &blk
      @context = { }
      @context_stack = { }
      @previous = { }
      @logger = nil

      opts.each do | k, v |
        s = "#{k}="
        if respond_to?(s)
          send(s, v) 
          opts.delete(k)
        end
      end

      build &blk if block_given?
    end


    # Begins building Statemachine by evaluating block.
    def build &blk
      raise ArgumentError, "expected block" unless block_given?
      instance_eval &blk
      @result
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
        superstate.submachine = sm 
        sm.superstate = superstate
      end

      _with_context(:state, nil) do
        _with_context(:start_state, nil) do 
          _with_context(:end_state, nil) do
            _with_context(:transitions, [ ]) do
              _with_context(:namespace, sm) do
                _with_context(:statemachine, sm) do 
                  instance_eval &blk if blk
                
                # Set start, end states.
                sm.start_state = _find_state(@context[:start_state]) if @context[:start_state]
                sm.end_state   = _find_state(@context[:end_state])   if @context[:end_state]
                
#=begin
                # Create transitions.
                @context[:transitions].each do | t |
                  _create_transition! t
                end
#=end
              end # statemachine
              end # namespace
            end # transitions
          end # end_state
        end # start_state
      end # state
      
      sm
    end


    # Defines the start state.
    def start_state state
      @context[:start_state] = state
      self
    end


    # Defines the end state.
    def end_state state
      @context[:end_state] = state
      self
    end


    # Creates a state.
    #
    # Syntax:
    #
    #   state :name
    #   state :name, :option_1 => 'foo'
    #   state :name do
    #     state :substate_1
    #     state :substate_2
    #   end
    #
    def state name, opts = { }, &blk
      opts[:name] = name

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
      
      opts[:_block] = blk if block_given?
      opts[:_owner] = _owner
      # opts[:_namespaces] = @context[:namespaces].reverse
      opts[:statemachine] = @context[:statemachine]
      
      @context[:transitions] << opts
      # _find_transition opts
      
      self
    end
    

    # Dispatches method to the current context.
    def method_missing sel, *args, &blk
      if @current && @current.respond_to?(sel)
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
   

    # Determine what object (a Statemachine or a (super)State) should own
    # a new State if one is created.
    def _owner
      # If the current object is a State,
      # the owner is the current superstate.
      # Else:
      # The owner of the State is the current Statemachine.
      owner = @context[:state] || @context[:statemachine]
      
      owner
    end



    # Locates a state by name or creates a new object.
    def _find_state opts, create = true, owner = nil, namespaces = nil
      raise ArgumentError, "invalid opts #{opts.inspect}" unless opts

      # $stderr.puts "_find_state #{opts.inspect}, #{create.inspect} from #{caller(1).first}" if ! create

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
        raise ArgumentError, "given #{opts.inspect}"
      end

      name = name.split(SEP) if String === name
 
      # @logger = $stderr if name == :a

      # Determine owner.
      owner ||= opts.delete(:_owner) if opts[:_owner]
      owner ||= _owner unless owner
      raise Exception, "Cannot determine owner for new State #{name.inspect}" unless owner

      # Attempt to locate existing State object.
      case name
      when nil
        raise ArgumentError, "State name not specified" unless name

      # If Array is given, start at root Statemachine.
      when Array
        path = name
        name = path.pop.to_sym
        owner = @result
        _log "  looking for path #{path.inspect} name #{name.inspect}"
        path.each do | e |
          break unless owner
          # $stderr.puts "  owner = #{owner.inspect}"
          owner = _find_state(e.to_sym, create, owner)
        end
        raise ArgumentError, "Cannot locate State #{name.inspect} in #{owner.inspect}" unless owner

        # Find existing State by name in owner.
        state = owner.states[name]

      # Search up namespaces till Object is found is found.
      else
        state = nil

        # Try owner first.
        if owner
          _log "  looking for #{name.inspect} directly in owner = #{owner.inspect}:"
          state = owner.states[name]
        end
      end


      _log "  state = #{state.inspect} in #{owner.inspect}"

=begin
      $stderr.puts "owner = #{owner.inspect}"
      $stderr.puts "caller = #{caller(0)[0 .. 4] * "\n  "}"
      $stderr.puts "state = #{state.inspect}"
=end

      # Create a new one, if requested.
      if create && ! state
        opts[:name] = name
        opts[:statemachine] ||= @context[:statemachine]
        state = State.new opts
        owner.add_state! state
        _log "  created #{state.inspect}"
      else
        if state
          state.options = opts
        end
      end
      
      state
    end


    # Called after all States have been created.
    def _create_transition! opts
      namespaces = opts.delete(:_namespaces)
      owner = opts.delete(:_owner)
      blk = opts.delete(:_block)

      _log "_create_transition! #{opts.inspect}"

      opts[:source] = _find_state opts[:source], :create, owner, namespaces
      opts[:target] = _find_state opts[:target], :create, owner, namespaces

      _log "  #{opts.inspect}"
       
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


    def _log msg
      case @logger
      when ::IO
        msg = "#{self.class} #{msg}"
        @logger.puts msg
      end
    end

  end # class

end # module


###############################################################################
# EOF
