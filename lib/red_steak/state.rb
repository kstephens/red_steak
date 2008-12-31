
module RedSteak

  # A State in a StateMachine.
  # A State may have a submachine.
  class State < Vertex
    # This state type, :start, :end or nil.
    attr_accessor :state_type # NOT UML AT ALL

    # The behavior executed upon entry to the transtion.
    attr_accessor :entry

    # The behavior executed when it is transitioned out of.
    attr_accessor :exit

    # The behavior executed when it is transitioned into.
    attr_accessor :doActivity

    # This state's submachine, or nil.
    attr_accessor :submachine # UML

    # List of Pseudostates.
    attr_reader :connectionPoint # UML


    def initialize opts = { }
      @state_type = nil
      @entry = nil
      @doActivity = nil
      @exit = nil
      @submachine = nil
      @connectionPoint = NamedArray.new([ ])
      super
    end


    def deepen_copy! copier, src
      super

      @submachine = copier[@submachine]
      @connectionPoint = copier[@connectionPoint]
    end


    def superstate
      @stateMachine && @stateMachine.submachineState 
    end

 
    # Substate axis.
    def state
      @submachine ? @submachine.state : NamedArray::EMPTY
    end


    # Adds a Pseudostate to this State.
    def add_connectionPoint! s
      _log { "add_connectionPoint! #{s.inspect}" }

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
      _log { "remove_connectionPoint! #{s.inspect}" }

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


    # Returns an array of all ancestor states.
    def ancestors
      @ancestors ||=
        begin
          x = [ self ]
          if ss = superstate
            x.push(*ss.ancestors)
          end
          
          NamedArray.new(x.freeze, :state)
        end
    end


    # Called by Machine when State is entered.
    def entry! machine, args
      _behavior! :entry, machine, args
    end


    # Called by Machine when State is exited.
    def exit! machine, args
      _behavior! :exit, machine, args
    end

    # Called by Machine when State is transitioned to.
    def doActivity! machine, args
      _behavior! :doActivity, machine, args
    end


    # Called after this State is added to the StateMachine.
    def state_added! statemachine
      transitions_changed!
    end


    # Called after a State removed from its StateMachine.
    def state_removed! statemachine
      transitions_changed!
    end


    # Adds a Pseudostate to this State.
    def add_connectionPoint! s
      _log { "add_connectionPoint! #{s.inspect}" }

      if @connectionPoint.find { | x | x.name == s.name }
        raise ArgumentError, "connectionPoint named #{s.name.inspect} already exists"
      end

      @ownedMember << s # ownedElement?!?!
      @connectionPoint << s
      s.state = self

      # Notify.
      s.connectionPoint_added! self

      s
    end


    # Removes a Pseudostate from this Statemachine.
    def remove_connectionPoint! s
      _log { "remove_connectionPoint! #{s.inspect}" }

      @ownedMember.delete(s) # ownedElement?!?!
      @connectionPoint.delete(s)
      s.state = nil

      # Notify.
      s.connectionPoint_removed! self

      self
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
