module RedSteak

  # Base class for all RedSteak errors.
  class Error < Exception
    # Transition is unknown by name.
    class UnknownTransition < self; end

    # Transition between states is impossible.
    class InvalidTransition < self; end
    
    # Transition between two states is not possible due
    # to a guard.
    class CannotTransition < self; end
    
    # More than one transitions between two states is possible.
    class AmbiguousTransition < self; end

    # Unexpected recursion detected.
    class UnexpectedRecursion < self; end

    # Feature is not implemented, yet.
    class NotImplemented < self; end

    # Transition is already pending.
    class TransitionPending < self; end
  end

end

