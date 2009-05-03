
module RedSteak

  # A StateMachine object.
  class StateMachine < Namespace

    # List of State objects.
    # subsets ownedMember
    attr_reader :states # not UML
    alias :state :states # UML

    # List of Pseudostate objects.
    # subsets ownedMember
    attr_reader :connectionPoint # UML

    # List of Transition objects.
    attr_reader :transitions # not UML
    alias :transition :transitions # UML

    # The enclosing State if this is a submachine.
    attr_accessor :submachineState # UML
    alias :superstate :submachineState # not UML
    alias :superstate= :submachineState= # not UML

    # The start state.
    attr_accessor :start_state # not UML

    # The end state.
    attr_accessor :end_state # not UML

    # The logging object.
    # Can be a Log4r::Logger or IO object.
    attr_accessor :logger

    # Log level method Symbol if Log4r::Logger === logger.
    attr_accessor :log_level


    def initialize opts
      @states = NamedArray.new([ ], :state)
      @transitions = NamedArray.new([ ])
      @submachineState = nil
      @start_state = nil
      @end_state = nil

      @logger = nil
      @log_level = :debug

      @s = @t = nil
      super
    end
    

    def deepen_copy! copier, src
      super

      @states = copier[@states]
      @transitions = copier[@transitions]
      @submachineState = copier[@submachineState]

      @start_state = copier[@start_state]
      @end_state   = copier[@end_state]
    end


    # Returns the outer-most StateMachine.
    def rootStateMachine
      @submachineState ? superstatemachine.rootStateMachine : self
    end


    # Sets the start state.
    def start_state= x
      @start_state = x
      if x
        @start_state.stateMachine = self
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
        @end_state.stateMachine = self
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
      @submachineState && @submachineState.stateMachine
    end


    # Adds a State to this StateMachine.
    def add_state! s
      _log { "add_state! #{s.inspect}" }

      if @states.find { | x | x.name == s.name }
        raise ArgumentError, "state named #{s.name.inspect} already exists"
      end

      add_ownedMember!(s)
      @states << s
      s.stateMachine = self

      # Notify.
      s.state_added! self

      s
    end


    # Removes a State from this StateMachine.
    # Also removes any Transitions associated with the State.
    # List of Transitions removed is returned.
    def remove_state! s
      _log { "remove_state! #{s.inspect}" }

      transitions = s.transitions

      remove_ownedMember!(s)
      @states.delete(s)
      s.stateMachine = nil

      s.transitions.each do | t |
        remove_transition! t
      end

      # Notify.
      s.state_removed! self

      transitions
    end


    # Adds a Pseudostate to this StateMachine.
    def add_connectionPoint! s
      _log { "add_connectionPoint! #{s.inspect}" }

      if @connectionPoint.find { | x | x.name == s.name }
        raise ArgumentError, "connectionPoint named #{s.name.inspect} already exists"
      end

      @ownedMember << s
      @connectionPoint << s
      s.stateMachine = self

      # Notify.
      s.connectionPoint_added! self

      s
    end


    # Removes a Pseudostate from this StateMachine.
    def remove_connectionPoint! s
      _log { "remove_Connection! #{s.inspect}" }

      @ownedMember.delete(s)
      @connectionPoint.delete(s)
      s.stateMachine = nil

      s.transitions.each do | t |
        remove_transition! t
      end

      # Notify.
      s.connectionPoint_removed! self

      self
    end


    # Adds a Transition to this StateMachine.
    def add_transition! t
      _log { "add_transition! #{t.inspect}" }

      if @transitions.find { | x | x.name == t.name }
        raise ArgumentError, "transition named #{s.name.inspect} already exists"
      end

      @transitions << t
      t.stateMachine = self

      # Notify.
      t.target.transition_added! t
      t.source.transition_added! t

      t
    end


    # Removes a Transition from this StateMachine.
    def remove_transition! t
      _log "remove_transition! #{t.inspect}"

      @transitions.delete(t)
      t.stateMachine = nil

      # Notify.
      if t.source
        t.source.transition_removed! t
        t.source = nil
      end

      if t.target
        t.target.transition_removed! t
        t.target = nil
      end

      self
    end


    # Returns a list of validation errors.
    def _validate errors = [ ]
      errors << :no_start_state unless start_state
      errors << :no_end_state unless end_state
      states.each do | s |
        s.validate errors
      end
      transitions.each do | t |
        t.validate errors
      end
      errors
    end

    
    # Returns the path name for this statemachine.
    def to_a
      if ss = superstate
        x = ss.stateMachine.to_a + ss.to_a
      else
        x = [ name ]
      end
      # x += [ name ]
      x
    end


    # Creates a new Builder to augment an existing StateMachine.
    def self.build opts = { }, &blk
      b = Builder.new(opts)
      if block_given?
        b.build &blk
        b.result
      else
        b
      end
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


    # Creates a new Machine for this StateMachine.
    def machine opts = { }
      opts[:stateMachine] ||= self
      Machine.new(opts)
    end


    ##################################################################

    def inspect
      "#<#{self.class} #{to_s}>"
    end


    def _log msg = nil
      case 
      when IO === @logger
        msg ||= yield
        @logger.puts "#{self.to_s} #{msg}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        msg ||= yield
        @logger.send(log_level || :debug, msg)
      when (x = superstatemachine)
        x._log(msg) { yield }
      end
    end


  end # class

end # module


###############################################################################
# EOF
