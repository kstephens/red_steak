
module RedSteak

  # A State in a StateMachine.
  # A State may have a submachine.
  class State < Vertex
    # This State's type: :start, :end or nil.
    attr_accessor :state_type # NOT UML AT ALL

    # The behavior executed upon entry to this State.
    # Can be a Symbol or a Proc.
    attr_accessor :entry # UML

    # The behavior executed when it is transitioned out of.
    # Can be a Symbol or a Proc.
    attr_accessor :exit # UML 

    # The behavior executed when it is transitioned into.
    # Can be a Symbol or a Proc.
    attr_accessor :doActivity # UML

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
      self.ancestors.include?(x)
    end


    # Returns true if this State is a superstate of x.
    # All States are superstates of themselves.
    def is_a_superstate_of? x
      x.ancestors.include?(self)
    end


    # A state with isComposite=true is said to be a composite state. A composite state is a state that contains at least one
    #   region. Default value is false.
    def isComposite
      ! ! @submachine
    end
    # Non-UML alias
    alias :is_composite? :isComposite

    # A state with isOrthogonal=true is said to be an orthogonal composite state. An orthogonal composite state contains
    # two or more regions. Default value is false.
    def isOrthogonal
      raise Error::NotImplemented, :message => :isOrthogonal, :object => self
    end
    # Non-UML alias
    alias :is_orthogonal? :isOrthogonal

    # A state with isSimple=true is said to be a simple state. A simple state does not have any regions and it does not refer
    #  to any submachine state machine. Default value is true.
    def isSimple
      raise Error::NotImplemented, :message => :isSimple, :object => self
    end
    # Non-UML alias
    alias :is_simple? :isSimple

    # A state with isSubmachineState=true is said to be a submachine state. Such a state refers to a state machine
    # (submachine). Default value is false.
    def isSubmachineState
      ! ! @submachine
    end
    # Non-UML alias
    alias :is_submachine_state? :isSubmachineState


    # Returns a NamedArray of all ancestor States.
    # self is the first element.
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


    # Removes a Pseudostate from this StateMachine.
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
      errors << :state_without_transitions unless transition.size != 0
      case
      when end_state?
        errors << :end_state_cannot_be_reached unless source.select{|x| x != self}.size != 0
        errors << :end_state_has_outbound_transitions unless target.size == 0
      when start_state?
        errors << :start_state_has_no_outbound_transitions unless target.size != 0
      else
        errors << :state_has_no_inbound_transitions unless source.select{|x| x != self}.size != 0
        errors << :state_has_no_outbound_transitions unless target.select{|x| x != self}.size != 0
      end
      if submachine
        errors << :end_state_has_substates unless ! end_state?
      end
    end

  end # class

end # module


###############################################################################
# EOF
