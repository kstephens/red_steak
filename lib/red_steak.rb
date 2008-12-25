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
#
module RedSteak
  EMPTY_ARRAY = [ ].freeze
  EMPTY_HASH =  { }.freeze

  # Transition is unknown by name.
  class UnknownTransitionError < Exception; end

  # Transition between states is impossible.
  class InvalidTransitionError < Exception; end

  # Transition between two states is not possible due
  # to a guard.
  class CannotTransitionError < Exception; end
  
  # Possible transitions between two states can follow more than
  # transition.
  class AmbigousTransitionError < Exception; end


  # Base class for RedSteak objects.
  class Base 
    attr_accessor :name
    attr_reader :_proto
    attr_reader :_options

    def initialize opts = EMPTY_HASH
      @name = nil
      @_proto = nil
      @_options = nil
      self._options = opts
      @_proto ||= self
    end


    # Sets all options.
    def _options= opts
      # If some options are already set, merge them.
      if @_options
        return @_options if opts.empty?
        @_options.merge(_dup_opts opts)
      else
        @_options = _dup_opts opts
      end

      # Scan options for setters.
      @_options.each do | k, v |
        s = "#{k}="
        if respond_to? s
          # $stderr.puts "#{self.class} #{self.object_id} s = #{s.inspect}, v = #{v.inspect}"
          send s, v
          @_options.delete k
        end
      end

      @_options
    end


    # Sets the name as a Symbol.
    def name= x
      @name = x && x.to_sym
      x
    end

    def _dup_opts opts
      h = { }
      opts.each do | k, v |
        k = k.to_sym
        case v
        when String, Array, Hash
          v = v.dup
        end
        h[k] = v
      end
      h
    end

    def dup
      x = super
      x.dup_deepen!
      x
    end

    def dup_deepen!
      @_options = _dup_opts @_options
    end

    # Returns the name as a String.
    def to_s
      name.to_s
    end

    def to_a
      [ name ]
    end

    # Returns the class and the name as a String.
    def inspect
      "#<#{self.class} #{self.name.inspect}>"
    end


    # Called by subclasses to notify/query the context object for specific actions.
    def _notify! action, args, sm = nil
      args ||= EMPTY_ARRAY
      method = _options[action] || (sm && _options[action]) || action
      # $stderr.puts "  _notify #{self.inspect} #{action.inspect} method = #{method.inspect}"
      c ||= (sm || self).context
      # $stderr.puts "    c = #{c.inspect}"
      if c
        case
        when Symbol === method && (c.respond_to?(method))
          c.send(method, self, *args)
        when Proc === method
          method.call(self, *args)
        else
          nil
        end
      else
        nil
      end
    end


=begin
    # Delegates to current context object.
    def method_missing sel, *args, &blk
      # $stderr.puts "#{self}#method_missing #{sel.inspect} #{args}"
      cntx = statemachine.context
      if cntx && cntx.respond_to?(sel)
        return cntx.send(sel, *args, &blk)
      end
      # $stderr.puts "  #{caller.join("\n  ")}"
      super
    end
=end
  end # class


  # Simple Array proxy for looking up States and Transitions by name.
  class ArrayDelegator
    def initialize del, sel
      @del, @sel = del, sel
    end

    def [] pattern
      case pattern
      when Integer
        _elements[pattern]
      else
        _elements.find { | e | e === pattern }
      end
    end

    def method_missing sel, *args, &blk
      _elements.send(sel, *args, &blk)
    end

    private 

    def _elements
      @del.send(@sel)
    end

  end


  # A Statemachine object.
  class Statemachine < Base
    # The list of all states.
    attr_reader :states

    # The list of all transitions.
    attr_reader :transitions

    # The superstate if this is a substatemachine.
    attr_accessor :superstate

    # The start state.
    attr_accessor :start_state

    # The end state.
    attr_accessor :end_state

    # The current state.
    attr_reader :state
    
    # The receiver of all methods missing inside Statemachine, State, and Transition.
    #
    # This object also recieves transition notifications:
    #
    # * enter_state!(state, *args)
    # * exit_state!(state, *args)
    # * before_transition!(trans, *args)
    # * after_transition!(trans, *args)
    # * during_transition!(trans, *args)
    # * can_transition?(trans, *args)
    #
    attr_accessor :context

    # History of all transitions.
    attr_accessor :history
    
    # If true, each transition is kept in #history.
    attr_accessor :history_enabled

    # If true, history of substates is kept.
    attr_accessor :deep_history

    # The logging object.
    # Can be a Log4r::Logger or IO object.
    attr_accessor :logger

    # Log level method Symbol for Log4r::Logger.
    attr_accessor :log_level


    def initialize opts
      @state = nil
      @start_state = nil
      @end_state = nil
      @states = [ ]
      @transitions = [ ]
      @history_enabled = false
      @history = [ ]
      @logger = nil
      super
    end
    

    # Sets the start state.
    def start_state= x
      @start_state = x
      if x
        @start_state.statemachine = self
        @states.each do | s |
          s.state_type = nil if s.start_state?
        end
        x.state_type = :start
      end
      x
    end


    # Sets the end state.
    def end_state= x
      @end_state = x
      if x 
        @end_state.statemachine = self
        @states.each do | s |
          s.state_type = nil if s.end_state?
        end
        x.state_type = :end
      end
      x
    end


    # Returns an Array of States indexable by name.
    def s
      @s ||= ArrayDelegator.new(self, :states)
    end


    # Returns an Array of Transitions indexable by name.
    def t
      @t ||= ArrayDelegator.new(self, :transitions)
    end

    def statemachine
      self
    end

    def superstatemachine
      @superstate && @superstate.statemachine
    end

    def dup_deepen!
      super

      # Duplicate states and transitions in event of augmentation.
      @states = @states.dup
      @transitions = @transitions.dup
=begin
      if @start_state
        @start_state = @start_state.dup
        @start_state.statemachine = self
      end
=end
      # If state is active, dup it to reattach it to this statemachine.
      if @state
        @state = @state.dup
        @state.statemachine = self
      end

      # Deepen history, if available.
      @history = @history && @history.dup
    end


    # Returns ture if we are at the start state.
    def at_start?
      @state.nil? || @state._proto == @start_state
    end


    # Returns true if we are at the end state.
    def at_end?
      @state._proto == @end_state
    end


    # Go to the start state.
    def start!
      @state = nil
      goto_state! start_state
    end


    # Returns true if a transition is possible from the current state.
    # Queries the transitions' guards.
    def can_transition? trans, *args
      trans = trans.to_sym unless Symbol === trans

      trans = transitions.select do | t |
        t.from_state === @state &&
        t.can_transition?(self, *args)
      end

      trans.size > 0
    end


    # Returns true if a non-ambigious transition is possible from the current state
    # to the given state.
    # Queries the transitions' guards.
    def can_transition_to? state, *args
      transitions_to(state, *args).size == 1
    end


    # Returns a list of valid transitions from current
    # state to the specified state.
    def transitions_to state, *args
      state = state.to_sym unless Symbol === state

      # $stderr.puts "  #{@state.inspect} transitions_from => #{@state.transitions_from.inspect}"

      trans = @state.transitions_from.select do | t |
        t.to_state === state &&
        t.can_transition?(self, *args)
      end

      # $stderr.puts "  #{@state.inspect} transitions_to(#{state.inspect}) => #{trans.inspect}"

      trans
    end


    # Attempt to transition from current state to another state.
    # This assumes that there is not more than one transition
    # from one state to another.
    def transition_to! state, *args
      trans = transitions_to(state, *args)

      case trans.size
      when 0
        raise UnknownTransitionError, state
      when 1
        transition!(trans.first, *args)
      else
        raise AmbigousTransitionError, state
      end
    end


    # Execute a transition from the current state.
    def transition! name, *args
      if Transition === name
        trans = name
        name = trans.name

        _log "transition! #{name.inspect}"
        
=begin
        if @state === trans.from_state
          $stderr.puts "    @state is from_state for #{trans.inspect}"
        else
          $stderr.puts "    @state.statemachine.to_a           = #{@state.statemachine.to_a.inspect}"
          $stderr.puts "    trans.from_state.statemachine.to_a = #{trans.from_state.statemachine.to_a.inspect}"

        end
        if trans.can_transition?(self, *args)
          $stderr.puts "    can_transition?() for #{trans.inspect}"
        end
=end

        trans = nil unless @state === trans.from_state && trans.can_transition?(self, *args)
      else
        name = name.to_sym unless Symbol === name
        
        # start! unless @state
        
        _log "transition! #{name.inspect}"
        
        # Find a valid transition.
        trans = @state.transitions_from.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          t.can_transition?(self, *args)
        end

        if trans.size > 1
          raise AmbigousTransitionError, "from #{@state.name.inspect} to #{name.inspect}"
        end

        trans = trans.first
      end

      if trans
        execute_transition!(trans, *args)
      else
        raise CannotTransitionError, name
      end
    end


    # Adds a State to this Statemachine.
    def add_state! s
      _log "add_state! #{s.inspect}"

      if @states.find { | x | x.name == s.name }
        raise ArgumentError, "state of named #{s.name.inspect} already exists"
      end

      @states << s
      s.statemachine = self

      # Attach to superstate.
      if ss = superstate
        s.superstate = ss
      end

      # Notify.
      s.state_added! self

      s
    end


    # Removes a State from this Statemachine.
    # Also removes any Transitions associated with the State.
    # List of Transitions removed is returned.
    def remove_state! s
      _log "remove_state! #{state.inspect}"

      transitions = s.transitions

      @states.delete(s)
      s.statemachine = nil

      transitions.each do | t |
        remove_transition! t
      end

      # Notify.
      s.state_removed! self

      transitions
    end


    # Adds a Transition to this Statemachine.
    def add_transition! t
      _log "add_transition! #{t.inspect}"

      if @transitions.find { | x | x.name == t.name }
        raise ArgumentError, "transition named #{s.name.inspect} already exists"
      end

      @transitions << t
      t.statemachine = self

      # Notify.
      t.to_state.transition_added! self
      t.from_state.transition_added! self

      t
    end


    # Removes a Transition from this Statemachine.
    def remove_transition! t
      _log "remove_transition! #{t.inspect}"

      @transitions.delete(t)
      t.statemachine = nil

      # Notify.
      t.to_state.transition_removed! self
      t.from_state.transition_removed! self

      self
    end


    # Returns a list of validation errors.
    def validate errors = nil
      errors ||= [ ]
      errors << [ :no_start_state ] unless start_state
      errors << [ :no_end_state ] unless end_state
      states.each do | s |
        errors << [ :state_without_transitions, s ] if s.transitions.empty?
        # $stderr.puts "  #{s.inspect} from_states = #{s.from_states.inspect}"
        # $stderr.puts "  #{s.inspect} to_states   = #{s.to_states.inspect}"
        case
        when s.end_state?
          errors << [ :end_state_cannot_be_reached, s ] if s.from_states.select{|x| x != s}.empty?
          errors << [ :end_state_has_outbound_transitions, s ] unless s.to_states.empty?
        when s.start_state?
          errors << [ :start_state_has_no_outbound_transitions, s ] if s.to_states.empty?
        else
          errors << [ :state_has_no_inbound_transitions, s ] if s.from_states.select{|x| x != s}.empty?
          errors << [ :state_has_no_outbound_transitions, s ] if s.to_states.select{|x| x != s}.empty?
        end
        if ssm = s.substatemachine
          errors << [ :end_state_has_substates, s ] if s.end_state?
          ssm.validate errors
        end
      end
      errors
    end

    
    # Returns true if this statemachine is valid.
    def valid?
      validate.empty?
    end


    def to_a
      if ss = superstate
        x = ss.statemachine.to_a
        x += [ ss.name ]
      else
        x = [ ]
      end
      x += [ @_proto.name ]
      x
    end


    def inspect
      "#<#{self.class} #{to_a.inspect}>"
    end


    ##################################################################
    # Dot graph support
    #

    # Returns the Dot name for this statemachine.
    def to_dot_name
      "#{superstate ? superstate.to_dot_name : name}"
    end


    # Returns the Dot label for this Statemachine.
    def to_dot_label
      @superstate ? "#{@superstate.statemachine.name}::#{name}" : name.to_s
    end


    # Renders this Statemachine as Dot syntax.
    def to_dot f, opts = { }
      opts[:root_statemachine] ||= self

      type = @superstate ? "subgraph #{to_dot_name}" : "digraph"
      do_graph = true

      f.puts "\n// {#{inspect}"
      f.puts "#{type} {" if do_graph
      f.puts %Q{  label = #{to_dot_label.inspect}}

      f.puts %Q{  #{(to_dot_name + "_START").inspect} [ shape="rectangle", label="#{to_dot_label} START", style=filled, fillcolor=black, fontcolor=white ]; }

      states.each { | x | x.to_dot f, self, opts }

      transitions.each { | x | x.to_dot f, self, opts }

      f.puts "}" if do_graph
      f.puts "// } #{inspect}\n"
    end 
    

    #####################################

    # Creates a new Builder to augment an existing Statemachine.
    def builder opts = { }, &blk
      b = Builder.new
      if block_given?
        b.statemachine(self, opts, &blk)
        self
      else
        b
      end
    end


    ##################################################################


    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.to_a.inspect} #{(state && state.to_a).inspect} #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, *args)
      when (x = superstatemachine)
        x._log *args
      end
    end


    ##################################################################
    # History support
    #


    # Returns an Array of Hashes containing:
    #
    #  :time
    #  :previous_state
    #  :transition
    #  :new_state
    #
    def history
      @history || 
        EMPTY_ARRAY
    end


    # Clears current history.
    def clear_history!
      @history = nil
    end


    # Returns the full history, if deep_history is in effect.
    def full_history
      if (ssm = superstatemachine) && ssm.deep_history
        ssm.full_history
      else
        self.history
      end
    end


    # Records a new history record.
    def record_history! hash = nil
      if @history_enabled || @deep_history
        hash ||= yield
        # $stderr.puts "  HISTORY #{@history.size} #{hash.inspect}"
        (@history ||= [ ]) << hash
      end

      if (ssm = superstatemachine) && ssm.deep_history
        hash ||= yield
        ssm.record_history! hash
      end
    end


    private

    # Executes transition.
    def execute_transition! trans, *args
      _log "execute_transition! #{(trans.to_a).inspect}"

      old_state = @state

      trans.before_transition!(self, *args)

      goto_state!(trans.to_state, *args) do 
        trans.during_transition!(self, *args)
      end
      
      trans.after_transition!(self, *args)
      
      record_history! do 
        {
          :time => Time.now.gmtime,
          :previous_state => old_state, 
          :transition => trans, 
          :new_state => @state,
        }
      end

      self
    end


    # Moves from one state machine to another.
    #
    # Notifies exit_state!
    # If a block is given, yield to it before entering new state.
    # Notifies enter_state!
    #
    def goto_state! state, *args
      old_state = @state

      # Notify of exiting state.
      if @state
        _log "exit_state! #{@state.to_a.inspect}"
        @state.exit_state!(*args)
      end

      # Yield to block before changing state.
      yield if block_given?
      
      # Move to next state buy cloning the State object.
      @state = state.dup
      @state.statemachine = self
      if ssm = @state.substatemachine
        # Clone the substate's statemachine.
        ssm = ssm.dup

        # Set the substates statemachine to the clone.
        @state.substatemachine = ssm

        # Associate the substatemachine with this state.
        ssm.superstate = @state

        # Start the substatemachine.
        ssm.start!

        # Associate the start substate's to this state.
        ssm.state.superstate = @state
      end

      # Notify of entering state.
      _log "enter_state! #{state.to_a.inspect}"
      @state.enter_state!(*args)

      self

    rescue Exception => err
      # Revert back to old state.
      @state = old_state
      raise err
    end

  end # class


  # A state in a statemachine.
  # A state may contain another statemachine.
  class State < Base
    # This state's statemachine.
    attr_accessor :statemachine

    # This state type, :start, :end or nil.
    attr_accessor :state_type

    # This state's superstate.
    # This is the containing State for this statemachine.
    attr_accessor :superstate

    # This state's substatemachine, or nil.
    attr_accessor :substatemachine

    # The context for enter_state!, exit_state!
    attr_accessor :context


    def intialize opts
      @statemachine = nil
      @state_type = nil
      @superstate = nil
      @substatemachine = nil
      @context = nil
      super
    end


    # Returns a new State object and dups any substatemachines.
    def dup_deepen!
      super
=begin
      if @substatemachine
        @substatemachine = @substatemachine.dup
        @substatemachine.superstate = self
      end
=end
    end


    # Returns the local context or the statemachine's context.
    def context
      @context || 
        statemachine.context
    end


    # Returns this state's substatemathine's state.
    def substate
      @substatemachine && @substatemachine.state
    end


    # Returns true if this a start state.
    def start_state?
      @state_type == :start
    end


    # Returns true if this an end state.
    def end_state?
      @state_type == :end
    end


    # Clears caches of related transitions.
    def transitions_changed!
      # $stderr.puts "  #{name.inspect} transitions_changed!"

      @transitions =
        @transitions_to =
        @transitions_from = 
        @to_states =
        @from_states =
        nil
    end


    # Called after a Transition is connected to this state.
    def transition_added! statemachine
      transitions_changed!
      _notify! :transition_added!, nil, statemachine
    end


    # Called after a Transition removed from this state.
    def transition_removed! statemachine
      transitions_changed!
      _notify! :transition_removed!, nil, statemachine
    end


    # Returns a list of Transitions to or from this State.
    def transitions
      @transitions ||=
        statemachine.transitions.select do | t | 
          t.to_state === self.name || t.from_state === self.name
        end.freeze
    end


    # Returns a list of Transitions to this State.
    # May include Transitions that leave from this State.
    def transitions_to
      @transitions_to ||=
        transitions.select { | t | t.to_state === self.name }.freeze
    end


    # Returns a list of Transitions from this State.
    # May include Transitions that return to this State.
    def transitions_from
      @transitions_from ||=
        transitions.select { | t | t.from_state === self.name }.freeze
    end


    # Returns a list of States that are immediately transitional from this one.
    def to_states
      @to_states ||=
        transitions_from.map { | t | t.to_state }.uniq.freeze
    end


    # Returns a list of States that are immediately transitional to this one.
    def from_states
      @from_states ||=
        transitions_to.map { | t | t.from_state }.uniq.freeze
    end


    # Returns true if this State matches x.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        (self == x) ||
        (self._proto == x._proto) ||
        (@name === x.name && 
         statemachine.to_a === x.statemachine.to_a) :
        x === @name
    end
    

    # Clients can override.
    def enter_state! *args
=begin
      if @substatemachine
        @substatemachine = @substatemachine.dup
        @substatemachine.superstate = self

        @substatemachine.start! # ???
        @substatemachine.state.superstate = self
      end
=end
      _notify! :enter_state!, args
    end


    # Clients can override.
    def exit_state! *args
      _notify! :exit_state!, args
    end


    # Called after a State is connected to this state.
    def state_added! statemachine
      _notify! :state_added!, [ self ], statemachine
    end


    # Called after a State removed from this state.
    def state_removed! statemachine
      transitions_changed!
      _notify! :state_removed!, [ self ], statemachine
    end


    # Returns an array representation of this State.
    # Includes superstates and substates.
    def to_a dir = nil
      if superstate
        superstate.to_a
      else
        to_a_substate
      end
    end


    # Returns an array representation of this State and its substates.
    def to_a_substate
      x = [ name ]
      if substate
        x += substate.to_a_substate
      end
      x
    end


    # Returns the string representation of this State.
    def to_s
      "[ #{to_a * ' '} ]"
    end

    
    def inspect
      "#<#{self.class} #{to_a.inspect}>"
    end

    
    def _log *args
      statemachine._log(*args)
    end


    # Returns the Dot name for this state.
    def to_dot_name
      "#{statemachine.to_dot_name}_#{name}" # .inspect
    end
    

    # Returns the Dot syntax for this state.
    def to_dot f, sm, opts
      dot_opts = {
        :color => :black,
        :label => name.to_s,
        :style => :filled,
      }

      case
        # when @substatemachine
        # :egg
      when end_state?
        dot_opts[:shape] = :rectangle
        dot_opts[:fillcolor] = :black
        dot_opts[:fontcolor] = :white
      else
        dot_opts[:shape] = :oval
        dot_opts[:fillcolor] = :white
        dot_opts[:fontcolor] = :black
      end

      if opts[:show_history]
        sequence = [ ]

        opts[:root_statemachine].history.each_with_index do | hist, i |
          if (s0 = hist[:previous_state] === self) || 
             (s1 = hist[:new_state] === self)
            # $stderr.puts "hist = #{hist.inspect} i = #{i.inspect}"
            case
            when s0
              sequence << i
            when s1
              sequence << i + 1
            end
          end
        end

        sequence.uniq!
        sequence.sort!
        unless sequence.empty?
          if opts[:show_history_sequence] 
            dot_opts[:label] += ": (#{sequence * ', '})"
          end
          dot_opts[:fillcolor] = :grey
          dot_opts[:fontcolor] = :black
        end
      end


      f.puts "\n// #{self.inspect}"
      f.puts %Q{#{to_dot_name.inspect} [ shape="#{dot_opts[:shape]}", label=#{dot_opts[:label].inspect}, style=#{dot_opts[:style]}, color=#{dot_opts[:color]}, fillcolor=#{dot_opts[:fillcolor]}, fontcolor=#{dot_opts[:fontcolor]} ];}

      if start_state?
        f.puts "#{(statemachine.to_dot_name + '_START').inspect} -> #{to_dot_name.inspect};"
      end

      if @substatemachine
        @substatemachine.to_dot f, opts
        f.puts "#{to_dot_name.inspect} -> #{(@substatemachine.to_dot_name + '_START').inspect} [ style=dashed ];"
      end
    end


    # Delegate other methods to substatemachine, if exists.
    def method_missing sel, *args, &blk
      if @substatemachine && @substatemachine.respond_to?(sel)
        return @substatemachine.send(sel, *args, &blk)
      end
      super
    end

  end # class


  # Represents a transition from one state to another state in a statemachine.
  class Transition < Base
    # The statemachine of this transition.
    attr_accessor :statemachine

    # The origin state.
    attr_accessor :from_state

    # The destination state.
    attr_accessor :to_state

    # The context for can_transition?, before_transition!, during_transition!, after_transition!
    attr_accessor :context


    # Returns the local context or the statemachine.context.
    def context(sm = statemachine)
      @context || 
        sm.context
    end


    # Returns true if X matches this transition.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        (x == self) ||
        (x._proto == self._proto) ||
        (
         x.name === self.name &&
         statemachine.to_a === x.statemachine.to_a
        ) :
        x === self.name
    end


    # Clients can override.
    def can_transition? sm, *args
      result = _notify! :can_transition?, args, sm
      result.nil? ? true : result
    end

    # Clients can override.
    def before_transition! sm, *args
      _notify! :before_transition!, args, sm
      self
    end

    # Clients can override.
    def during_transition! sm, *args
      _notify! :during_transition!, args, sm
      self
    end

    # Clients can override.
    def after_transition! sm, *args
      _notify! :after_transition!, args, sm
      self
    end

    def inspect
      "#<#{self.class} #{from_state.name} === #{self.name} ==> #{to_state.name}>" 
    end

    def _log *args
      statemachine._log(*args)
    end

    # Renders the Dot syntax for this Transition.
    def to_dot f, sm, opts
      f.puts "\n// #{self.inspect}"

      dot_opts = { 
        :label => name.to_s,
        :color => :black,
      }

      sequence = [ ]

      if opts[:show_history]
        # $stderr.puts "\n  trans = #{self.inspect}, sm = #{self.statemachine.inspect}"
        opts[:root_statemachine].history.each_with_index do | hist, i |
          if hist[:transition] === self
            # $stderr.puts "  #{i} hist = #{hist.inspect}"
            sequence << (i + 1)
          end
        end

        sequence.sort!
        sequence.uniq!
      end

      unless sequence.empty?
        sequence.each do | seq |
          f.puts "#{from_state.to_dot_name.inspect} -> #{to_state.to_dot_name.inspect} [ label=#{seq.to_s.inspect}, color=gray, fontcolor=gray ];"
        end
      end

      f.puts "#{from_state.to_dot_name.inspect} -> #{to_state.to_dot_name.inspect} [ label=#{dot_opts[:label].inspect}, color=#{dot_opts[:color]} ];"

    end

  end # class


  # DSL for building state machines.
  class Builder
    # Returns the top-level statemachine.
    attr_accessor :result

    def initialize &blk
      @context = { }
      @context_stack = { }
      build &blk if block_given?
    end

    def build &blk
      instance_eval &blk
      result
    end


    ##################################################################
    # DSL methods
    #

    # Creates a new statemachine or augments an existing one.
    #
    # Create syntax:
    #
    #   sm = builder.build do 
    #     statemachine :my_statemachine do
    #       start_state :a
    #       end_state   :end
    #       state :a
    #       state :b
    #       state :end
    #       transition :a, :b
    #       transition :b, :end
    #     end
    #   end
    #
    # Augmenting syntax:
    #
    #   sm.builder do 
    #     state :c
    #     transition :a, :c
    #     transition :c, :end
    #   end
    #
    def statemachine name = nil, opts = { }, &blk
      # Create a sub state machine?
      superstate = @context[:state]
      if superstate
        name = superstate.name
      end
      raise(ArgumentError, 'invalid name') unless name

      case name
      when Statemachine
        sm = name
        name = sm.name
      else
        name = name.to_sym unless Symbol === name
        
        opts[:name] = name
        sm = Statemachine.new opts
      end

      @result ||= sm

      # Attach state to substate machine.
      if superstate
        superstate.substatemachine = sm 
        sm.superstate = superstate
      end

      _with_context(:state, nil) do
        _with_context(:start_state, nil) do 
          _with_context(:end_state, nil) do
            _with_context(:statemachine, sm) do 
              if blk
                instance_eval &blk 
                
                # Do this at the end.
                sm.start_state = _find_state(@context[:start_state]) if @context[:start_state]
                sm.end_state   = _find_state(@context[:end_state])   if @context[:end_state]

=begin
                # Associate substates with their superstate
                # prototypes.
                if superstate
                  sm.states.each do | x |
                    x.superstate = superstate
                  end
                end
=end
              end
            end
          end
        end
      end
    end


    # Defines the start state.
    def start_state state
      @context[:start_state] = state
    end


    # Defines the end state.
    def end_state state
      @context[:end_state] = state
    end


    # Creates a state.
    def state name, opts = { }, &blk
      opts[:name] = name
      s = _find_state opts
      _with_context :state, s do 
        instance_eval &blk if blk
      end
    end


    # Creates a transition between two states.
    #
    # Syntax:
    #
    #   state :a do 
    #     transition :b
    #   end
    #   state :b
    #
    # Creates a transition named :'a->b' from state :a to state :b.
    #
    #   state :a
    #   state :b
    #   transition :a, :b
    #
    # Creates a transition name :'a->b' from state :a to state :b.
    #
    #   state :a do
    #     transition :b, :name => :a_to_b
    #   end
    #   state b:
    #
    # Creates a transition named :a_to_b from state :a to state :b.
    def transition *args, &blk
      if Hash === args.last
        opts = args.pop
      else
        opts = { }
      end

      case args.size
      when 1 # to_state
        opts[:from_state] = @context[:state]
        opts[:to_state] = args.first
      when 2 # from_state, to_state
        opts[:from_state], opts[:to_state] = *args
      else
        raise(ArgumentError)
      end

      raise ArgumentError unless opts[:from_state]
      raise ArgumentError unless opts[:to_state]
      
      opts[:from_state] = _find_state opts[:from_state]
      opts[:to_state]   = _find_state opts[:to_state]

      t = _find_transition opts
      _with_context :transition, t do
        instance_eval &blk if blk
      end
    end


    # Dispatches method to the current context.
    def method_missing sel, *args, &blk
      if @current
        return @current.send(sel, *args, &blk)
      end
      super
    end


    private

    def _with_context name, val
      current_save = @current
 
      (@context_stack[name] ||= [ ]).push(@context[name])
      
      @current = 
        @context[name] = 
        val
      
      yield
      
    ensure
      @current = current_save
      
      @context[name] = @context_stack[name].pop
    end
   

    # Locates a state by name or creates a new object.
    def _find_state opts, create = true
      $stderr.puts "_find_state #{opts.inspect}, #{create.inspect} from #{caller(1).first}" if ! create

      raise ArgumentError, "opts" unless opts

      name = nil
      case opts
      when String, Symbol
        name = opts.to_sym
        opts = { }
      when Hash
        name = opts[:name].to_sym
      when State
        return opts
      else
        raise ArgumentError, "given #{opts.inspect}"
      end

      raise ArgumentError, "name" unless name

      s = @context[:statemachine].states.find do | x | 
        name === x.name
      end

      if create && ! s
        opts[:name] = name
        opts[:statemachine] = @context[:statemachine]
        s = State.new opts
        @context[:statemachine].add_state! s
      else
        if s 
          s._options = opts
        end
      end

      
      s
    end

    # Locates a transition by name or creates a new object.
    def _find_transition opts
      raise ArgumentError, "opts expected Hash" unless Hash === opts

      opts[:from_state] = _find_state opts[:from_state]
      opts[:to_state]   = _find_state opts[:to_state]
      opts[:name] ||= "#{opts[:from_state].name}->#{opts[:to_state].name}".to_sym

      t = @context[:statemachine].transitions.find do | x |
        opts[:name] == x.name
      end
      
      unless t
        opts[:statemachine] = @context[:statemachine]
        t = Transition.new opts
        @context[:statemachine].add_transition! t
      else
        if t
          opts.delete(:name)
          t._options = opts
        end
      end
      
      t
    end
    
  end # class

end # module


###############################################################################
# EOF
