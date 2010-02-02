# An extensible, instantiable, cloneable statemachine written in Ruby.
#
# Features:
#
# * Implements UML 2.1 StateMachine semantics (partially).
# * Builder DSL simplifies construction and modification of complex StateMachine objects.
# * The execution of the StateMachine is managed by an external Machine object;
# * Multiple Machine objects can walk the same Statemachine without side-effects.
# * Submachines are supported, a State may have an imbedded StateMachine.
# * StateMachine and Machines objects can be serialized.
# * StateMachine objects can be instantiated then cloned via StateMachine#copy.
# * StateMachine objects can be modified on-the-fly.
# * Context objects can be notified of Transition execution and State changes.
# * Transition guard and effect behaviors are supported.
# * State entry, doActivity and exit behaviors are supported.
# * StateMachine, State and Transition objects can be extended with metadata.
# * History of Transitions can be logged per Machine.
# * StateMachine and Machine#history records can be rendered as Dot syntax and SVG; See link:example/red_steak-loan_application-09.dot.svg.
#
module RedSteak
  EMPTY_ARRAY = [ ].freeze
  EMPTY_HASH =  { }.freeze
  EMPTY_STRING = ''.freeze

  SEP = '::'.freeze

end # module

# Support
require 'red_steak/error'
require 'red_steak/base'

# UML Metamodel
require 'red_steak/named_element'
require 'red_steak/namespace'
require 'red_steak/state_machine'
#require 'red_steak/region' # NOT IMPLEMENTED, YET!
require 'red_steak/vertex'
require 'red_steak/state'
require 'red_steak/transition'
require 'red_steak/final_state'

# API
require 'red_steak/builder'
require 'red_steak/machine'
require 'red_steak/event'

# Rendering
require 'red_steak/dot'


###############################################################################
# EOF
