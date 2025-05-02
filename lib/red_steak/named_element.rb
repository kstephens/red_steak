module RedSteak
  # Base class for all elements in a StateMachine.
  class NamedElement < Base
    # The Namespace of this NamedElement.
    attr_accessor :namespace

    # The StateMachine that owns this object.
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML
    alias :statemachine= :stateMachine= # not UML

    def initialize opts
      @namespace = nil
      @stateMachine = nil
      super
    end

    def freeze
      return self if frozen?
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
    def _behavior! action, machine, info, default_value = nil
      event = info.event
      action, *args = event
      machine.as_current do
      raise Error, 'action is not a Symbol' unless Symbol === action
      args ||= EMPTY_ARRAY
      # Determine the behavior.
      behavior = (force_send = (send(action) || @stateMachine.options[action])) || action
      pp(_behavior!: {action: action, behavior: behavior, force_send: force_send})
      case
      when Proc === behavior
        return behavior.call(*args)
      when Symbol === behavior && (c = machine.context)
        # Don't force send unless the object responds.
        unless force_send
          force_send = c.respond_to?(behavior)
        end
        if force_send
          meth_arity = c.method(behavior).arity rescue 0
          case
          when meth_arity < 0
          when meth_arity == args.size
          when meth_arity == 0
            args = EMPTY_ARRAY
          else
            args = args[0 ... meth_arity]
          end
          pp(_behavior!: {send: {behavior: behavior, args: args}})
          return c.send(behavior, *args)
        end
      end
      end
      default_value
    end

    def inspect
      "#<#{self.class} #{@stateMachine.to_s} #{to_s}>"
    end
  end
end
