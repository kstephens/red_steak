
module RedSteak

  # Represents a transition from one state to another state in a statemachine.
  class Transition < NamedElement
    # See TransitionKind.
    attr_accessor :kind

    # The State that this Transition moves from.
    attr_accessor :source

    # The State the Transition move to.
    attr_accessor :target

    # A guard is a constraint.
    attr_accessor :guard
    
    # Specifies optional behavior to be performed when the transition fires.
    attr_accessor :effect


    def deepen_copy! copier, src
      super

      @source = copier[@source]
      @target = copier[@target]
    end


    # Returns true if X matches this transition.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      case x
      when self.class
        x == self
      else
        x === @name
      end
    end


    def participants
      NamedArray.new([ @source, @target ].uniq, :states)
    end


    # Called by Machine to check guard.
    def guard? machine, args
      result = _behavior! :guard, machine, args
      result.nil? ? true : result
    end


    # Called by Machine to perform #effect when transition fires.
    def effect! machine, args
      _behavior! :effect, machine, args
      self
    end


    def inspect
      "#<#{self.class} #{name.inspect} #{source.to_s} -> #{target.to_s}>" 
    end


    def _log *args
      statemachine._log(*args)
    end

  end # class

end # module


###############################################################################
# EOF
