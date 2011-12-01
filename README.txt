RedSteak - a clonable, mutable UML 2 StateMachine for Ruby.

Features:

* Implements UML 2.1 StateMachines (partially).
* StateMachines can be instantiated then cloned via StateMachine#copy.
* Submachines are supported, a state may have an imbedded StateMachine.
* Builder DSL simplifies construction of complex statemachines.
* StateMachines can be serialized.
* StateMachines can be modified on-the-fly.
* Context objects can be notfied of transitions, enter and exit actions.
* Context objects can be used to create transition guards.
* StateMachines, States and Transitions are objects that can be extended with metadata.
* History of transitions can be kept.
* Multiple machines can execute the same statemachine without side-effects.
* StateMachines and their transition history can be rendered as Dot syntax.

