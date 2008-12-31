
module RedSteak

  # Abstract superclass for State and Pseudostate
  class Vertex < NamedElement
    # This vertex kind.
    attr_accessor :kind

    # List of Transitions into this Vertex.
    attr_reader :incoming

    # List of Transitions away from this Vertex.
    attr_reader :outgoing


    def initialize opts = { }
      @kind = nil
      transitions_changed!
      @incoming = NamedArray.new([ ], :state)
      @outgoing = NamedArray.new([ ], :state)
      super
    end


    def deepen_copy! copier, src
      super
      transitions_changed!
      @incoming = copier[@incoming]
      @outgoing = copier[@outgoing]
    end


    # Clears caches of related transitions.
    def transitions_changed!
      # $stderr.puts "  #{name.inspect} transitions_changed!"

      @transition =
        @target =
        @source =
        nil
    end


    # Called after a Transition is connected to this state.
    def transition_added! transition
      transitions_changed!
      if self == transition.target
        @incoming << transition unless @incoming.include?(transition)
      end
      if self == transition.source
        @outgoing << transition unless @outgoing.include?(transition)
      end

      # $stderr.puts "transition_added! #{self.inspect} #{@incoming.inspect} #{@outgoing.inspect}"
    end


    # Called after a Transition removed from this state.
    def transition_removed! transition
      transitions_changed!
    end


    # Returns a list of Transitions incoming to or outgoing from this State.
    def transition
      @transition ||= 
        NamedArray.new(
                       (incoming + outgoing).uniq.freeze                
                       )
    end
    alias :transitions :transition


    # Returns a list of States that are immediately transitional from this one.
    def target
      @target ||=
        NamedArray.new(
                       outgoing.map { | t | t.target }.uniq.freeze,
                       :state
                       )
    end
    alias :targets :target


    # Returns a list of States that are immediately transitional to this one.
    def source
      @source ||=
        NamedArray.new(
                       incoming.map { | t | t.source }.uniq.freeze,
                       :state
                       )
    end
    alias :sources :source


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
      if ss = @stateMachine.submachineState
        ss.to_a << @name
      else
        [ @name ]
      end
    end

  end # class

end # module


###############################################################################
# EOF
