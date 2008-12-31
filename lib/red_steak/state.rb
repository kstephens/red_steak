
module RedSteak

  # A state in a statemachine.
  # A state may have substates.
  # A state may contain another statemachine.
  class State < Vertex
    # This state type, :start, :end or nil.
    attr_accessor :state_type

    # This state's substates.
    attr_reader   :substates # not UML

    # The behavior executed upon entry to the transtion.
    attr_accessor :enter

    # The behavior executed when it is transitioned into.
    attr_accessor :doActivity

    # The behavior executed when it is transitioned out of.
    attr_accessor :exit

    # This state's submachine, or nil.
    attr_accessor :submachine # UML


    # For state <-> substate traversal.
    alias :states :substates # NOT UML
    alias :state :states # UML


    def initialize opts = { }
      @state_type = nil
      @enter = nil
      @doActivity = nil
      @exit = nil
      @superstate = nil
      @substates = NamedArray.new([ ], :states)
      @submachine = nil
      super
      # $stderr.puts "initialize: @substates = #{@substates.inspect}"
    end


    def deepen_copy! copier, src
      super

      @superstate = copier[@superstate]
      @substates = copier[@substates]
      @submachine = copier[@submachine]
    end


    # Adds a substate to this Statemachine.
    def add_substate! s
      _log "add_substate! #{s.inspect}"

      if @substates.find { | x | x.name == s.name }
        raise ArgumentError, "substate named #{s.name.inspect} already exists"
      end

      @substates << s
      s.superstate = self
      s.statemachine = @stateMachine

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
      _log "remove_substate! #{s.inspect}"

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


    # Adds a Pseudostate to this State.
    def add_connectionPoint! s
      _log "add_connectionPoint! #{s.inspect}"

      if @connectionPoint.find { | x | x.name == s.name }
        raise ArgumentError, "connectionPoint named #{s.name.inspect} already exists"
      end

      @connectionPoint << s
      s.state = self

      # Notify.
      s.connectionPoint_added! self

      s
    end


    # Removes a Pseudostate from this State.
    def remove_connectionPoint! s
      _log "remove_connectionPoint! #{s.inspect}"

      @connectionPoint.delete(s)
      s.state = nil

      # Notify.
      s.connectionPoint_removed! self

      self
    end


    # Returns true if this a start state.
    def start_state?
      @state_type == :start
    end


    # Returns true if this an end state.
    def end_state?
      @state_type == :end
    end


    # Returns true if this State matches x or is a substate of x.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      case x
      when self.class
        self.is_a_substate_of?(x)
      else
        super
      end
    end

    
    # Returns true if this State is a substate of x.
    # All States are substates of themselves.
    def is_a_substate_of? x
      s = self
      while s
        return true if s == x
        s = s.superstate
      end
      false
    end


    # Called by Machine when State is entered.
    def enter! machine, args
      _behavior! :enter, machine, args
    end


    # Called by Machine when State is exited.
    def exit! machine, args
      _behavior! :exit, machine, args
    end

    # Called by Machine when State is transitioned to.
    def doActivity! machine, args
      _behavior! :doActivity, machine, args
    end


    # Called after this State is added to the statemachine.
    def state_added! statemachine
      transitions_changed!
    end


    # Called after a State removed from its statemachine.
    def state_removed! statemachine
      transitions_changed!
    end


    # Called after a Transition is connected to this state.
    def transition_added! t
      # $stderr.puts caller(0)[0 .. 3] * "\n  "
      transitions_changed!
    end


    # Called after a Transition is removed from this state.
    def transition_removed! t
      # $stderr.puts caller(0)[0 .. 3] * "\n  "
      transitions_changed!
    end


    def _validate errors
      errors << :state_without_transitions unless transitionsize != 0
      case
      when end_state?
        errors << :end_state_cannot_be_reached unless sourceselect{|x| x != s}.size != 0
        errors << :end_state_has_outbound_transitions unless targetsize == 0
      when start_state?
        errors << :start_state_has_no_outbound_transitions unless targetsize != 0
      else
        errors << :state_has_no_inbound_transitions unless sourceselect{|x| x != s}.size != 0
        errors << :state_has_no_outbound_transitions unless targetselect{|x| x != s}.size != 0
      end
      if submachine
        errors << :end_state_has_substates unless ! end_state?
      end
    end

  end # class

end # module


###############################################################################
# EOF
