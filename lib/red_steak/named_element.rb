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
    def _behavior! meta_action, action, default_value = nil
      _typecheck! Symbol, meta_action
      args = action.event # + [action]
      # Determine the behavior.
      behavior = (force_send = (send(meta_action) || @stateMachine.options[meta_action])) || meta_action
      # pp(_behavior!: {meta_action: meta_action, behavior: behavior, force_send: force_send})
      case behavior
      when Proc
        args = _trim_arity!(args, behavior.arity)
        # pp(_behavior!: {call: {behavior: behavior, args: args}})
        action.as_current do
          return behavior.call(*args)
        end
      when Symbol
        context = action.context
        # Don't force send unless the object responds.
        if force_send || context.respond_to?(behavior)
          args = _trim_arity!(args, (context.method(behavior).arity rescue 0))
          # pp(_behavior!: {send: {behavior: behavior, args: args}})
          # binding.pry if behavior == :a
          action.as_current do
            begin
              return context.send(behavior, *args)
            rescue => exc
              binding.pry
              raise
            end
          end
        end
      end
      # pp(_behavior!: {skipping: true, behavior: behavior, args: args})
      default_value
    end

    def _trim_arity! args, arity
      if arity >= 0 && args.size > arity
        args[0 ... arity]
      else
        args
      end
    end

    def inspect
      "#<#{self.class} #{@stateMachine.to_s} #{to_s}>"
    end
  end
end
