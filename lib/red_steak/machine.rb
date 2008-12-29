# require 'debug'

require 'red_steak'

module RedSteak
  # Machine walks the Transitions between States of a Statemachine.
  # It can record history.
  class Machine < Base
    # The submachine, if any.
    attr_accessor :sub

    # The supermachine, if any.
    attr_accessor :sup

    # The Statemachine.
    attr_accessor :statemachine

    # The current state in the statemachine.
    attr_reader :state
    
    # The receiver of all methods missing inside Statemachine, State, and Transition.
    #
    # This object also recieves transition notifications:
    #
    # * can_transition?(trans, *args)
    # * before_transition!(trans, *args)
    # * enter_state!(state, *args)
    # * during_transition!(trans, *args)
    # * exit_state!(state, *args)
    # * after_transition!(trans, *args)
    #
    # States and Transitions many define specific context objects.
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

    # Log level method Symbol if Log4r::Logger === logger.
    attr_accessor :log_level


    def initialize opts
      @statemachine = nil
      @sub = @sup = nil
      @state = nil
      @history_enabled = false
      @history = [ ]
      @logger = nil
      super
    end
    

    def deepen_copy! copier, src
      super
      # Deepen history, if available.
      @history = @history && @history.dup
    end


    # Returns true if #start! has been called.
    def started?
      ! @state.nil?
    end


    # Returns ture if we are at the start state.
    def at_start?
      @state == @statemachine.start_state
    end


    # Returns true if we are at the end state.
    def at_end?
      @state == @statemachine.end_state
    end


    # Go to the start state.
    def start! *args
      @state = nil
      goto_state! @statemachine.start_state, args

      @history.clear if @history
      record_history! do 
        {
          :time => Time.now.gmtime,
          :previous_state => nil, 
          :transition => nil, 
          :new_state => @state,
        }
      end

      self
    end


    # Returns true if a transition is possible from the current state.
    # Queries the transitions' guards.
    def can_transition? trans, *args
      trans = trans.to_sym unless Symbol === trans

      trans = statemachine.transitions.select do | t |
        t.from_state == @state &&
        t.can_transition?(self, args)
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

      trans = @state.outgoing.select do | t |
        t.target === state &&
        t.can_transition?(self, args)
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
        raise Error::UnknownTransition, state
      when 1
        transition!(trans.first, *args)
      else
        raise Error::AmbiguousTransition, state
      end
    end


    # Execute a transition from the current state.
    def transition! name, *args
      if Transition === name
        trans = name
        name = trans.name

        _log "transition! #{name.inspect}"
        
        trans = nil unless @state === trans.source && trans.can_transition?(self, args)
      else
        name = name.to_sym unless Symbol === name
        
        # start! unless @state
        
        _log "transition! #{name.inspect}"
        
        # Find a valid outgoing transition.
        trans = @state.outgoing.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          t.can_transition?(self, args)
        end

        if trans.size > 1
          raise Error::AmbiguousTransition, "from #{@state.name.inspect} to #{name.inspect}"
        end

        trans = trans.first
      end

      if trans
        execute_transition!(trans, *args)
      else
        raise Error::CannotTransition, name
      end
    end


    def to_a
      x = [ @state && @state.name ]
      if sub
        x += sub.to_a
      end
      x
    end


    def inspect
      "#<#{self.class} #{@statemachine.name.inspect} #{to_a.inspect}>"
    end


    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.to_a.inspect} #{(state && state.to_a).inspect} #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, *args)
      when @sup
        @sup._log *args
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
      if @sup && @sup.deep_history
        @sup.full_history
      else
        history
      end
    end


    # Records a new history record.
    def record_history! hash = nil
      if @history_enabled || @deep_history
        hash ||= yield
        # $stderr.puts "  HISTORY #{@history.size} #{hash.inspect}"
        (@history ||= [ ]) << hash
      end

      if @sup && @sup.deep_history
        hash ||= yield
        @sup.record_history! hash
      end
    end


    private

    # Executes transition.
    def execute_transition! trans, *args
      _log "execute_transition! #{(trans.to_a).inspect}"

      old_state = @state

      trans.before_transition!(self, args)

      goto_state!(trans.target, args) do 
        trans.during_transition!(self, args)
      end
      
      trans.after_transition!(self, args)
      
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
    def goto_state! state, args
      old_state = @state

      # Notify of exiting state.
      if @state
        _log "exit_state! #{@state.to_a.inspect}"
        @state.exit_state!(self, args)
      end

      # Yield to block before changing state.
      yield if block_given?
      
      # Move to next state buy cloning the State object.
      @state = state
      if ssm = @state.substatemachine
        # Create a submachine.
        @sub = self.class.new(:sup => self, :statemachine => ssm)

        # Start the submachine.
        @sub.start!
      end

      # Notify of entering state.
      _log "enter_state! #{@state.to_a.inspect}"
      @state.enter_state!(self, args)

      self

    rescue Exception => err
      # Revert back to old state.
      @state = old_state
      raise err
    end

  end # class

end # module


###############################################################################
# EOF
