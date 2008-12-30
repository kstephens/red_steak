
module RedSteak

  # A state in a statemachine.
  # A state may have substates.
  # A state may contain another statemachine.
  class State < Vertex
    # This state type, :start, :end or nil.
    attr_accessor :state_type

    # This state's substates.
    attr_reader   :substates

    # The behavior executed upon entry to the transtion.
    attr_accessor :enter

    # The behavior executed when it is transitioned into.
    attr_accessor :doActivity

    # The behavior executed when it is transitioned out of.
    attr_accessor :exit

    # This state's substatemachine, or nil.
    attr_accessor :substatemachine


    # For state <-> substate traversal.
    alias :states :substates


    def initialize opts = { }
      @state_type = nil
      @enter = nil
      @doActivity = nil
      @exit = nil
      @superstate = nil
      @substates = NamedArray.new([ ], :states)
      @substatemachine = nil
      super
      # $stderr.puts "initialize: @substates = #{@substates.inspect}"
    end


    def deepen_copy! copier, src
      super

      @superstate = copier[@superstate]
      @substates = copier[@substates]
      @substatemachine = copier[@substatemachine]
    end


    # Adds a substate to this Statemachine.
    def add_substate! s
      _log "add_substate! #{s.inspect}"

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


    # Returns true if this State matches x.
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


=begin
    # Delegate other methods to substatemachine, if exists.
    def method_missing sel, *args, &blk
      if @substatemachine && @substatemachine.respond_to?(sel)
        return @substatemachine.send(sel, *args, &blk)
      end
      super
    end
=end

  end # class

end # module


###############################################################################
# EOF
