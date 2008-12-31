
module RedSteak

  # Base class for all elements in a Statemachine.
  class NamedElement < Base
    # The Namespace of this NamedElement.
    attr_accessor :namespace

    # The StateMachine that owns this object.
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML
    alias :statemachine= :stateMachine= # not UML
    
    def intialize opts
      @namespace = nil
      @stateMachine = nil
      super
    end
    
    
    def deepen_copy! copier, src
      super
      @namespace = copier[@namespace]
      @stateMachine = copier[@stateMachine]
    end


    
    def ownedMember_added! ns
    end


    def ownedMember_removed! ns
    end
    
    
    # Called by subclasses to notify/query the context object for specific actions.
    # Will get the method from local options or the StateMachine's options Hash.
    # The context is either the local object's context or the StateMachine's context.
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
    

    def inspect
      "#<#{self.class} #{@stateMachine.to_s} #{to_s}>"
    end


    def _log *args
      stateMachine._log(*args)
    end

  end # class

end # module


###############################################################################
# EOF
