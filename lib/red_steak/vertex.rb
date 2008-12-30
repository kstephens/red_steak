
module RedSteak

  # Abstract superclass for State and Pseudostate
  class Vertex < NamedElement
    # This vertex kind.
    attr_accessor :kind

    # This state's superstate.
    attr_accessor :superstate

    def intialize opts = { }
      @kind = nil
      @superstate = nil
      super
    end


    def deepen_copy! copier, src
      super

      transitions_changed!
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


    # Returns a list of Transitions incoming or outgoing this State.
    def transitions
      @transitions ||= 
        NamedArray.new(
                       statemachine.transitions.select { | t | 
                         t.source == self || t.target == self
                       }.freeze
                       )
    end


    # Returns a list of Transitions incoming to this State.
    # May include outgoing Transitions than return to this State.
    def incoming
      @incoming ||=
        NamedArray.new(
                       transitions.select { | t | t.target == self }.freeze
                       )
    end


    # Returns a list of Transitions outgoing from this State.
    # May include incoming Transitions that return to this State.
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
                       outgoing.map { | t | t.target }.uniq.freeze,
                       :states
                       )
    end


    # Returns a list of States that are immediately transitional to this one.
    def sources
      @sources ||=
        NamedArray.new(
                       incoming.map { | t | t.source }.uniq.freeze,
                       :states
                       )
    end


    # Returns true if this matches x.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      case x
      when self.class
        self == x
      when Symbol
        x === @name
      when String
        x.to_s === to_s
      when Regexp
        x === to_s
      else
        false
      end
    end


    # Returns an Array representation of this State.
    # Includes superstates and substates.
    def to_a
      if superstate
        superstate.to_a << @name
      else
        [ @name ]
      end
    end


    def inspect
      "#<#{self.class} #{@statemachine.to_s} #{to_s}>"
    end


    def _log *args
      statemachine._log(*args)
    end

  end # class

end # module


###############################################################################
# EOF
