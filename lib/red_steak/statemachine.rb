
module RedSteak

  # Base class for all elements in a Statemachine.
  class NamedElement < Base
    # The Statemachine that owns this object.
    attr_accessor :statemachine
    
    def intialize opts
      @statemachine = nil
      super
    end
    
    
    def deepen_copy! copier, src
      super
      @statemachine = copier[@statemachine]
    end
    
    
    # Called by subclasses to notify/query the context object for specific actions.
    # Will get the method from local options or the statemachine's options Hash.
    # The context is either the local object's context or the statemachine's context.
    def _notify! action, machine, args
      raise ArgumentError, 'action is not a Symbol' unless Symbol === action
      
      args ||= EMPTY_ARRAY
      method = 
        machine.options[action] ||
        @options[action] || 
        @statemachine.options[action] || 
        action
      # $stderr.puts "  _notify #{self.inspect} #{action.inspect} method = #{method.inspect}"
      case
      when Proc === method
        method.call(machine, self, *args)
      when Symbol === method && 
          (c = machine.context || @context) &&
          (c.respond_to?(method))
        c.send(method, machine, self, *args)
      else
        nil
      end
    end
    
  end # class
  


  # A Statemachine object.
  class Statemachine < Base

    # The list of all states.
    attr_reader :states

    # The list of all transitions.
    attr_reader :transitions

    # The superstate if this is a substatemachine.
    attr_accessor :superstate

    # The start state.
    attr_accessor :start_state

    # The end state.
    attr_accessor :end_state

    # The logging object.
    # Can be a Log4r::Logger or IO object.
    attr_accessor :logger

    # Log level method Symbol if Log4r::Logger === logger.
    attr_accessor :log_level


    def initialize opts
      @states = NamedArray.new([ ], :states)
      @transitions = NamedArray.new([ ])
      @superstate = nil
      @start_state = nil
      @end_state = nil

      @logger = nil
      @log_level = :debug

      @s = @t = nil
      super
    end
    

    def deepen_copy! copier, src
      super

      @superstate = copier[@superstate]

      @states = copier[@states]
      @transitions = copier[@transitions]

      @start_state = copier[@start_state]
      @end_state   = copier[@end_state]
    end


    # Sets the start state.
    def start_state= x
      @start_state = x
      if x
        @start_state.statemachine = self
        @states.each do | s |
          s.state_type = nil if s.start_state?
        end
        x.state_type = :start
      end
      x
    end


    # Sets the end state.
    def end_state= x
      @end_state = x
      if x 
        @end_state.statemachine = self
        @states.each do | s |
          s.state_type = nil if s.end_state?
        end
        x.state_type = :end
      end
      x
    end


    alias :s :states
    alias :t :transitions

    # Returns the superstatemachine of this State.
    def superstatemachine
      @superstate && @superstate.statemachine
    end


    # Adds a State to this Statemachine.
    def add_state! s
      _log "add_state! #{s.inspect}"

      if @states.find { | x | x.name == s.name }
        raise ArgumentError, "state named #{s.name.inspect} already exists"
      end

      @states << s
      s.statemachine = self

      # Attach to superstate.
      if ss = superstate
        s.superstate = ss
      end

      # Notify.
      s.state_added! self

      s
    end


    # Removes a State from this Statemachine.
    # Also removes any Transitions associated with the State.
    # List of Transitions removed is returned.
    def remove_state! s
      _log "remove_state! #{state.inspect}"

      transitions = s.transitions

      @states.delete(s)
      s.statemachine = nil

      transitions.each do | t |
        remove_transition! t
      end

      # Notify.
      s.state_removed! self

      transitions
    end


    # Adds a Transition to this Statemachine.
    def add_transition! t
      _log "add_transition! #{t.inspect}"

      if @transitions.find { | x | x.name == t.name }
        raise ArgumentError, "transition named #{s.name.inspect} already exists"
      end

      @transitions << t
      t.statemachine = self

      # Notify.
      t.target.transition_added! t
      t.source.transition_added! t

      t
    end


    # Removes a Transition from this Statemachine.
    def remove_transition! t
      _log "remove_transition! #{t.inspect}"

      @transitions.delete(t)
      t.statemachine = nil

      # Notify.
      if t.source
        t.source = nil
        t.source.transition_removed! t
      end

      if t.target
        t.target = nil
        t.target.transition_removed! t
      end

      self
    end


    # Returns a list of validation errors.
    def validate errors = nil
      errors ||= [ ]
      errors << [ :no_start_state ] unless start_state
      errors << [ :no_end_state ] unless end_state
      states.each do | s |
        errors << [ :state_without_transitions, s ] if s.transitions.empty?
        # $stderr.puts "  #{s.inspect} sources = #{s.sources.inspect}"
        # $stderr.puts "  #{s.inspect} targets   = #{s.targets.inspect}"
        case
        when s.end_state?
          errors << [ :end_state_cannot_be_reached, s ] if s.sources.select{|x| x != s}.empty?
          errors << [ :end_state_has_outbound_transitions, s ] unless s.targets.empty?
        when s.start_state?
          errors << [ :start_state_has_no_outbound_transitions, s ] if s.targets.empty?
        else
          errors << [ :state_has_no_inbound_transitions, s ] if s.sources.select{|x| x != s}.empty?
          errors << [ :state_has_no_outbound_transitions, s ] if s.targets.select{|x| x != s}.empty?
        end
        if ssm = s.substatemachine
          errors << [ :end_state_has_substates, s ] if s.end_state?
          ssm.validate errors
        end
      end
      errors
    end

    
    # Returns true if this statemachine is valid.
    def valid?
      validate.empty?
    end


    # Returns the path name for this statemachine.
    def to_a
      if ss = superstate
        x = ss.superstatemachine.to_a + ss.to_a
      else
        x = [ name ]
      end
      # x += [ name ]
      x
    end


    # Creates a new Builder to augment an existing Statemachine.
    # Executes block in builder, if given.
    def builder opts = { }, &blk
      b = Builder.new(opts)
      if block_given?
        b.statemachine(self, opts, &blk)
        self
      else
        b
      end
    end
    alias :build :builder


    # Creates a new Machine for this Statemachine.
    def machine opts = { }
      opts[:statemachine] ||= self
      Machine.new(opts)
    end


    ##################################################################


    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.to_a.inspect} #{(state && state.to_a).inspect} #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, *args)
      when (x = superstatemachine)
        x._log *args
      end
    end



  end # class

end # module


###############################################################################
# EOF
