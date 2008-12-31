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
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML

    # The current state in the statemachine.
    attr_reader :state
    
    # The receiver of all methods missing inside Statemachine, State, and Transition.
    #
    # This object also recieves transition notifications:
    #
    # * guard(machine, trans, *args)
    # * effect(machine, trans, *args)
    #
    # * entry(machine, state, *args)
    # * exit(machine, state, *args)
    # * doActivity(machine, state, *args)
    #
    attr_accessor :context

    # History of all transitions.
    #
    # An Array of Hash objects, each containing:
    # * :time - the Time the transition was completed.
    # * :transition - the Transtion object.
    # * :previous_state - the state before the transition.
    # * :new_state - the state after the transition.
    # 
    # start! will create an initial History entry 
    # where :transition and :previous_state is nil.
    #
    attr_accessor :history

    # Method called on history to append new record.
    attr_accessor :history_append

    # Method called on history to clear history.
    attr_accessor :history_clear

    # The logging object.
    # Can be a Log4r::Logger or IO object.
    attr_accessor :logger

    # Log level method Symbol if Log4r::Logger === logger.
    # Defaults to :debug.
    attr_accessor :log_level


    def initialize opts
      @stateMachine = nil
      @sub = @sup = nil
      @state = nil
      @history = nil
      @history_append = :<<
      @history_clear = :clear
      @logger = nil
      @log_level = :debug
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
      @state == @stateMachine.start_state
    end


    # Returns true if we are at the end state.
    def at_end?
      @state == @stateMachine.end_state
    end


    # Go to the start state.
    def start! *args
      @state = nil
      goto_state! @stateMachine.start_state, args
      self
    end

 
    # Forcefully sets state.
    def state= x
      case x
      when State
        state = x
      else
        state = @stateMachine.states[x]
      end
      goto_state! state
      
      self
    end


    def to_state state
      case state
      when State, nil
        state
      when String
        stateMachine.rootStateMachine.state[state]
      else
        stateMachine.state[state]
      end
    end
 

    # Returns true if a transition is possible from the current state.
    # Queries the transitions' guard.
    def guard? trans, *args
      trans = trans.to_sym unless Symbol === trans

      trans = @stateMachine.transition.select do | t |
        t.from_state == @state &&
        t.guard?(self, args)
      end

      trans.size > 0
    end


    # Returns true if a non-ambigious direct transition is possible from the current state
    # to the given state.
    # Queries the transitions' guards.
    def can_transition_to? state, *args
      transitions_to(state, *args).size == 1
    end


    # Returns a list of valid transitions from current
    # state to the specified state.
    def transitions_to state, *args
      state = to_state(state)

      trans = @state.outgoing.select do | t |
        t.target == state &&
          t.guard?(self, args)
      end

      trans
    end


    # Attempt to transition from current state to another state.
    # This assumes that there is not more than one transition
    # from one state to another.
    def transition_to! state, *args
      state = to_state(state)
      
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
        
        trans = nil unless @state === trans.source && trans.guard?(self, args)
      else
        name = name.to_sym unless Symbol === name
        
        # start! unless @state
        
        _log "transition! #{name.inspect}"
        
        # Find a valid outgoing transition.
        trans = @state.outgoing.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          t.guard?(self, args)
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
      "#<#{self.class} #{@stateMachine.name.inspect} #{to_a.inspect}>"
    end


    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.to_s} #{state.to_s} #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, *args)
      when @sup
        @sup._log *args
      end
    end


    ##################################################################
    # History support
    #


    # Clears current history.
    def clear_history!
      @history && @history.send(@history_clear)
    end


    # Records a new history record.
    # Supermachines are also notified.
    # Machine is the origin of the history record.
    def record_history! machine, hash = nil
      if @history
        hash ||= yield
        @history.send(@history_append, hash)
      end

      if @sup
        hash ||= yield
        @sup.record_history! machine, hash
      end

      self
    end


    private

    # Executes transition.
    #
    # 1) Transition's effect behavior is performed.
    # 2) Old State's exit behavior is performed.
    # 3) transition history is logged.
    # 4) New State's entry behavior is performed.
    # 5) New State's doAction behavior is performed.
    #
    def execute_transition! trans, *args
      _log "execute_transition! #{trans.inspect}"

      old_state = @state

      # Behavior: Transition effect.
      trans.effect!(self, args)
      
      _goto_state!(trans.target, args) do 
        record_history!(self) do 
          {
            :time => Time.now.gmtime,
            :previous_state => old_state, 
            :transition => trans, 
            :new_state => state,
          }
        end
        
      end
      
      self
    end


    # Moves directly to a State.
    #
    # Calls _goto_state!, clears history and adds initial history record.
    #
    def goto_state! state, args, &blk
      _goto_state! state, args, &blk

      clear_history!
      record_history!(self) do 
        {
          :time => Time.now.gmtime,
          :previous_state => nil, 
          :transition => nil, 
          :new_state => @state,
        }
      end
    end


    # Moves from one state machine to another.
    #
    # 1) Performs old State's exit behavior.
    # 2) If a block is given, yield to it after entering new state.
    # 3) Performs new State's entry behavior.
    #
    def _goto_state! state, args
      old_state = @state

      # If the state has a submachine,
      # start! it.
      if ssm = state.submachine
        if ss = ssm.start_state
          state = ssm.start_state
        end
      end

      from = old_state ? old_state.ancestors : EMPTY_ARRAY
      to = state ? state.ancestors : EMPTY_ARRAY

      # Behavior: exit state.
      if old_state && old_state != state
        (from - to).each do | s |
          _log "exit! #{s.inspect}"
          s.exit!(self, args)
        end
      end

      # Move to next state.
      @state = state

      # Yield to block.
      yield if block_given?
      
      # Behavior: entry state.
      if old_state != state
        (to - from).reverse.each do | s | 
          _log "entry! #{s.inspect}"
          s.entry!(self, args)
        end
      end

      # Behavior: doActivity.
      state.doActivity!(self, args)

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
