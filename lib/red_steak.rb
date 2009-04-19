# require 'debug'

# An extensible, instantiable, cloneable statemachine written in Ruby.
#
# Features:
#
# * Implements UML 2.1 StateMachines (partially).
# * StateMachines can be instantiated then cloned via StateMachine#copy.
# * Submachines are supported, a state may have an imbedded StateMachine.
# * Builder DSL simplifies construction and modification of complex statemachines.
# * StateMachines can be serialized.
# * StateMachines can be modified on-the-fly.
# * Context objects can be notified of transitions.
# * Context objects can be used to create transition guards.
# * StateMachines, States and Transitions are objects that can be extended with metadata.
# * History of transitions can be kept.
# * Multiple machines can walk the same statemachine without side-effects.
# * StateMachines and Machine#history can be rendered as Dot syntax and SVG.
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
require 'red_steak/vertex'
require 'red_steak/state'
require 'red_steak/transition'
require 'red_steak/final_state'

# API
require 'red_steak/builder'
require 'red_steak/machine'

# Rendering
require 'red_steak/dot'


###############################################################################
# EOF
