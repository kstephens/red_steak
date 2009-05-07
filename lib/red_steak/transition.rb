
module RedSteak

  # Represents a transition from one state to another state in a statemachine.
  class Transition < Namespace
    # See TransitionKind.
    attr_accessor :kind # UML

    # The State this Transition moves from.
    attr_accessor :source # UML

    # The State this Transition moves to.
    # This may be the same as the source State.
    attr_accessor :target # UML

    # A list of Triggers (Symbols) that can trigger this Transtion.
    attr_accessor :trigger # UML

    # A guard, if defined allows or prevents Transition from being queued or selected.
    # Can be a Symbol or a Proc.
    # If Symbol, it is the name of the method to call on the context.
    # Using a Symbol is preferred.
    attr_accessor :guard # UML
    
    # Specifies optional behavior to be performed when the Transition is fired.
    # Can be a Symbol or a Proc.
    # If Symbol, it is the name of the method to call on the context.
    # Using a Symbol is preferred.
    attr_accessor :effect # UML


    def initialize opts
      @kind = :external
      @trigger = EMPTY_ARRAY
      super
      @trigger = [ @trigger ] unless Array === @trigger
    end


    def deepen_copy! copier, src
      super

      @source = copier[@source]
      @target = copier[@target]
      @trigger = copier[@trigger]
      @participant = nil
    end


    # Returns true if X matches this Transition by name.x
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      case x
      when self.class
        x == self
      else
        x === @name
      end
    end


    # Returns the source and target.
    # FIXME: @paricipant needs to be invalidated if @source or @target change.
    def participant
      @participant ||=
        NamedArray.new([ @source, @target ].uniq.freeze, :state)
    end


    # Returns the first #trigger that matches the event.
    # Called by Machine#transitions_matching_event.
    # Returns nil if Transitions has no triggers or none that match.
    def matches_event? event
      @trigger.each do | t |
        return t if t === event.first
      end
      nil
    end


    # Called by Machine to check #guard.
    def guard? machine, args
      result = _behavior! :guard, machine, args, true
      result.nil? ? true : result
    end


    # Called by Machine to perform #effect when transition fires.
    def effect! machine, args
      _behavior! :effect, machine, args
      self
    end


    def inspect
      "#<#{self.class} #{@stateMachine.to_s} #{name} #{source.to_s} -> #{target.to_s}>" 
    end

  end # class

end # module


###############################################################################
# EOF
