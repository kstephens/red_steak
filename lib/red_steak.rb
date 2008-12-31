# require 'debug'

# An extensible, instantiable, cloneable statemachine written in Ruby.
#
# Features:
#
# * Implements UML 2.x StateMachines (partially).
# * Statemachines can be instantiated then cloned via #dup.
# * Submachines are supported, a state may have an imbedded statemachine.
# * Builder DSL simplifies construction of complex statemachines.
# * Statemachines can be serialized.
# * Statemachines can be modified on-the-fly.
# * Context objects can be notfied of transitions.
# * Context objects can be used to create transition guards.
# * Statemachines, States and Transitions are objects that can be extended with metadata.
# * History of transitions can be kept.
# * Multiple machines can walk the same statemachine without side-effects.
# * Statemachines can be rendered as Dot syntax.
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
require 'red_steak/statemachine'
require 'red_steak/vertex'
require 'red_steak/state'
require 'red_steak/transition'

# API
require 'red_steak/builder'
require 'red_steak/machine'

# Rendering
require 'red_steak/dot'


###############################################################################
# EOF
