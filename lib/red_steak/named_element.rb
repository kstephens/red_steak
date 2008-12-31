
module RedSteak

  # Base class for all elements in a Statemachine.
  class NamedElement < Base
    # The StateMachine that owns this object.
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML
    alias :statemachine= :stateMachine= # not UML
    
    def intialize opts
      @stateMachine = nil
      super
    end
    
    
    def deepen_copy! copier, src
      super
      @stateMachine = copier[@stateMachine]
    end
    
    
    # Called by subclasses to notify/query the context object for specific actions.
    # Will get the method from local options or the statemachine's options Hash.
    # The context is either the local object's context or the statemachine's context.
    def _behavior! action, machine, args
      raise ArgumentError, 'action is not a Symbol' unless Symbol === action
      
      args ||= EMPTY_ARRAY

      # Determine the behavior.
      behavior = 
        send(action) || 
        @stateMachine.options[action] || 
        action

      # $stderr.puts "  _behavior! #{self.inspect} #{action.inspect} behavior = #{behavior.inspect}"
      case
      when Proc === behavior
        behavior.call(machine, self, *args)
      when Symbol === behavior && 
          (c = machine.context) &&
          (c.respond_to?(behavior))
        c.send(behavior, machine, self, *args)
      else
        nil
      end
    end
    
  end # class

end # module


###############################################################################
# EOF
