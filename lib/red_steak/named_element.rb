
module RedSteak

  # Base class for all elements in a StateMachine.
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
    def _behavior! action, machine, event, default_value = nil
      raise ArgumentError, 'action is not a Symbol' unless Symbol === action
      
      # Determine the behavior.
      behavior = 
        (force_send = 
         (send(action) || 
          @stateMachine.options[action])) || 
        action

      # $stderr.puts "  _behavior! #{self.inspect} #{action.inspect} #{machine.inspect}: behavior = #{behavior.inspect}"

      case
      when Proc === behavior
        return behavior.call(machine, self, event)
      when Symbol === behavior && 
          (c = machine.context)

        # Don't force send unless the object responds.
        unless force_send
          force_send = c.respond_to?(behavior)
        end

        if force_send
          meth_arity = c.method(behavior).arity rescue 3
          case 
          when meth_arity == 0
            args = EMPTY_ARRAY
          when meth_arity < 0
            args = [ machine, self, event ]
          else
            args = [ machine, self, event ]
            args = [0 ... meth_arity]
          end
          # $stderr.puts "  _behavior! #{self.inspect} #{action.inspect} #{machine.inspect}\n    => #{c}.send(#{behavior.inspect}, *#{args.inspect})"
          return c.send(behavior, *args)
        end
      end
      default_value
    end
    

    def inspect
      "#<#{self.class} #{@stateMachine.to_s} #{to_s}>"
    end


    def _log msg = nil, &blk
      @stateMachine._log(msg, &blk)
    end

  end # class

end # module


###############################################################################
# EOF
