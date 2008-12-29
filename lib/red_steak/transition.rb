
module RedSteak

  # Represents a transition from one state to another state in a statemachine.
  class Transition < Statemachine::Element
    # The State that this Transition moves from.
    attr_accessor :source

    # The State the Transition move to.
    attr_accessor :target


    def deepen_copy! copier, src
      super

      @source = copier[@source]
      @target = copier[@target]
    end


    # Returns true if X matches this transition.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        (x == self) :
        x === self.name
    end


    # Clients can override.
    def can_transition? machine, args
      result = _notify! :can_transition?, machine, args
      result.nil? ? true : result
    end


    # Clients can override.
    def before_transition! machine, args
      _notify! :before_transition!, machine, args
      self
    end


    # Clients can override.
    def during_transition! machine, args
      _notify! :during_transition!, machine, args
      self
    end


    # Clients can override.
    def after_transition! machine, args
      _notify! :after_transition!, machine, args
      self
    end


    def inspect
      "#<#{self.class} #{name.inspect} #{source.name.inspect} -> #{target.name.inspect}>" 
    end


    def _log *args
      statemachine._log(*args)
    end

  end # class

end # module


###############################################################################
# EOF
