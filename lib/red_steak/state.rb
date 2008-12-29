
module RedSteak

  # A state in a statemachine.
  # A state may have substates.
  # A state may contain another statemachine.
  class State < Statemachine::Element
    # This state type, :start, :end or nil.
    attr_accessor :state_type

    # This state's superstate.
    attr_accessor :superstate

    # This state's substates.
    attr_reader   :substates

    # This state's substatemachine, or nil.
    attr_accessor :substatemachine


    alias :states :substates


    def intialize opts = { }
      @state_type = nil
      @superstate = nil
      @substates = NamedArray.new
      @substatemachine = nil
      super
    end


    def deepen_copy! copier, src
      super

      transitions_changed!

      @superstate = copier[@superstate]

      @substates = copier[@substates]

      @substatemachine = copier[@substatemachine]

    end


    # Adds a substate to this Statemachine.
    def add_substate! s
      _log "add_state! #{s.inspect}"

      if @substates.find { | x | x.name == s.name }
        raise ArgumentError, "substate named #{s.name.inspect} already exists"
      end

      @substates << s
      s.superstate = self
      s.statemachine = @statemachine

      # Attach to superstate.
      if ss = superstate
        s.superstate = ss
      end

      # Notify.
      s.state_added! self

      s
    end
    alias :add_state! :add_substate!


    # Removes a subtate from this State.
    # Also removes any Transitions associated with the State.
    # List of Transitions removed is returned.
    def remove_substate! s
      _log "remove_substate! #{state.inspect}"

      transitions = s.transitions

      @substates.delete(s)
      s.superstate = nil
      s.statemachine = nil

      transitions.each do | t |
        remove_transition! t
      end

      # Notify.
      # s.state_removed! self

      transitions
    end
    alias :remove_state! :remove_substate!


    # Returns true if this a start state.
    def start_state?
      @state_type == :start
    end


    # Returns true if this an end state.
    def end_state?
      @state_type == :end
    end


    # Clears caches of related transitions.
    def transitions_changed!
      # $stderr.puts "  #{name.inspect} transitions_changed!"

      @transitions =
        @outgoing =
        @incoming = 
        @targets =
        @sources =
        nil
    end


    # Called after a Transition is connected to this state.
    def transition_added! statemachine
      transitions_changed!
      # _notify! :transition_added!, nil, statemachine
    end


    # Called after a Transition removed from this state.
    def transition_removed! statemachine
      transitions_changed!
      # _notify! :transition_removed!, nil, statemachine
    end


    # Returns a list of Transitions to or from this State.
    def transitions
      @transitions ||= 
        NamedArray.new(
                       statemachine.transitions.select { | t | 
                         t.source == self || t.target == self
                       }.freeze
                       )
    end


    # Returns a list of Transitions incoming to this State.
    # May include Transitions that leave from this State.
    def incoming
      @incoming ||=
        NamedArray.new(
                       transitions.select { | t | t.target == self }.freeze
                       )
    end


    # Returns a list of Transitions outgoing from this State.
    # May include Transitions that return to this State.
    def outgoing
      @outgoing ||=
        NamedArray.new(
                       transitions.select { | t | t.source == self }.freeze
                       )
    end


    # Returns a list of States that are immediately transitional from this one.
    def targets
      @targets ||=
        NamedArray.new(
                       outgoing.map { | t | t.target }.uniq.freeze
                       )
    end


    # Returns a list of States that are immediately transitional to this one.
    def sources
      @sources ||=
        NamedArray.new(
                       incoming.map { | t | t.source }.uniq.freeze
                       )
    end


    # Returns true if this State matches x.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        (self == x) :
        x === @name
    end
    

    # Clients can override.
    def enter_state! machine, args
      _notify! :enter_state!, machine, args
    end


    # Clients can override.
    def exit_state! machine, args
      _notify! :exit_state!, machine, args
    end


    # Called after this State is added to the statemachine.
    def state_added! statemachine
      transitions_changed!
      # _notify! :transition_added!, [ self ], statemachine
    end


    # Called after a State removed from its statemachine.
    def state_removed! statemachine
      transitions_changed!
      # _notify! :transition_removed!, [ self ], statemachine
    end


    # Called after a Transition is connected to this state.
    def transition_added! t
      # $stderr.puts caller(0)[0 .. 3] * "\n  "
      transitions_changed!
      # _notify! :transition_added!, [ self ], statemachine
    end


    # Called after a Transition is removed from this state.
    def transition_removed! t
      # $stderr.puts caller(0)[0 .. 3] * "\n  "
      transitions_changed!
      # _notify! :transition_removed!, [ self ], statemachine
    end


    # Returns an Array representation of this State.
    # Includes superstates and substates.
    def to_a
      if superstate
        superstate.to_a << name
      else
        [ name ]
      end
    end


    # Returns the string representation of this State.
    def to_s
      to_a * '::'
    end

    
    def inspect
      "#<#{self.class} #{to_a.inspect}>"
    end

    
    def _log *args
      statemachine._log(*args)
    end


    # Delegate other methods to substatemachine, if exists.
    def method_missing sel, *args, &blk
      if @substatemachine && @substatemachine.respond_to?(sel)
        return @substatemachine.send(sel, *args, &blk)
      end
      super
    end

  end # class

end # module


###############################################################################
# EOF
