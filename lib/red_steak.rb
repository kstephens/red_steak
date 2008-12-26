# require 'debug'

# An extensible, instantiable, cloneable statemachine.
#
# Features:
#
# * Statemachines can be instantiated then cloned via #dup.
# * Substatemachines are supported, a state may have an imbedded statemachine.
# * Builder DSL simplifies construction of DSL.
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

end # module

require 'red_steak/error'
require 'red_steak/base'

require 'red_steak/statemachine'
require 'red_steak/state'
require 'red_steak/transition'
require 'red_steak/builder'
require 'red_steak/machine'
require 'red_steak/dot'


###############################################################################
# EOF
