# require 'debug'

require 'red_steak'

module RedSteak
  # Machine walks the Transitions between States of a StateMachine.
  #
  # Features:
  #
  # * It can record transition history.
  # * Multiple instances can "walk" the same StateMachine.
  # * Instances are easily serialized using Marshal.
  #
  # Example:
  #
  #   sm = RedSteak::Builder.new.build do
  #     ...
  #   end
  #
  #   class MyContext
  #     def guard(m, t) true; end
  #     def effect(m, t) ...; end
  #     def entry(m, s) ...; end
  #     def doActivity(m, s) ...; end
  #     def exit(m, s) ...; end
  #   end
  #
  #   # Synchronous Usage:
  #   m = sm.machine
  #   m.context = MyContext.new(...)
  #   m.start!
  #   m.run!
  #
  #   # Asynchronous Usage:
  #   m = sm.machine
  #   m.context = MyContext.new(...)
  #   m.start!
  #   m.run! do | m |
  #     application.do_something
  #     m.transition_to_next_state!
  #     application.do_something_else
  #   end
  #
  #   # Single-step Usage:
  #   m = sm.machine
  #   m.context = MyContext.new(...)
  #   m.start!
  #   m.transition!(:t1)
  #   m.run!(:single)
  #   m.transition1(:t2)
  #   m.run!(:single)
  #   ...
  #   
  class Machine < Base
    # The StateMachine.
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML

    # The current State in the statemachine.
    attr_reader :state

    # True if pause! was called during run!
    attr_reader :paused


    # This object recieves Transition and State behavior callbacks:
    #
    # Transition behaviors:
    #
    # * guard(machine, trans, *args)
    # * effect(machine, trans, *args)
    #
    # State behaviors:
    #
    # * entry(machine, state, *args)
    # * exit(machine, state, *args)
    # * doActivity(machine, state, *args)
    #
    # A Transition's :guard query behavior may be called multiple times before
    # a Transition is executed, therefore it should be free of side-effects.
    attr_accessor :context

    # History of all transitions.
    #
    # An collection of Hash objects, each containing:
    # * :time - the Time the transition was completed.
    # * :transition - the Transtion object.
    # * :previous_state - the state before the transition.
    # * :new_state - the state after the transition.
    # 
    # #start! will create an initial History entry 
    # where :transition and :previous_state is nil.
    #
    attr_accessor :history

    # Method called on #history to append new record.
    # Defaults to :<<, as applicable to an Array.
    attr_accessor :history_append

    # Method called on #history to clear history.
    # Defaults to :clear, as applicable to an Array.
    attr_accessor :history_clear

    # The logging object.
    # Can be a Log4r::Logger or IO object.
    attr_accessor :logger

    # Log level method Symbol if Log4r::Logger === logger.
    # Defaults to :debug.
    attr_accessor :log_level

    # If not #in_doActivity? AND
    # 1) If true, queueing a Transition will execute #run!.
    # 2) If :single, queueing a Transition will execute #run!(:single).
    #
    # THIS IS A BAD API IDEA AND MAY GO AWAY SOON!
    attr_accessor :auto_run

    # The queue of pending Transitions.
    attr_reader :transition_queue

    # The currently executing Transition.
    attr_reader :executing_transition


    def initialize opts
      @stateMachine = nil
      @state = nil
      @transition_queue = [ ]
      @history = nil
      @history_append = :<<
      @history_clear = :clear
      @logger = nil
      @log_level = :debug
      @auto_run = false

      @in_effect = false
      @in_entry = false
      @in_doActivity = false
      @in_exit = false
      @in_run = false
      @executing_transition = nil

      super
    end
    

    def deepen_copy! copier, src
      super
      @transition_queue = @transition_queue.dup
      # Deepen history, if available.
      @history = @history && @history.dup
    end

 
    # Returns true if #start! has been called.
    def started?
      ! @state.nil?
    end


    # Returns true if we are at the start state.
    def at_start?
      @state == @stateMachine.start_state
    end


    # Returns true if we are at the end state.
    def at_end?
      FinalState === @state || # UML
      @state == @stateMachine.end_state # not UML
    end


    # Go to the start State.
    # The State's entry and doActivity are executed.
    # Any transitions in doActivity are queued;
    # Queued transitions are fired only by #run!.
    def start! *args
      @state = nil
      goto_state! @stateMachine.start_state, args
    end


    # Run pending transitions.
    # 
    # Only the top-level #run! will process pending transitions,
    # run! has no effect if called recursively.
    # Returns self if run! is at the top-level, nil if a run! is already active.
    #
    # If %single is true, only one Transition is executed.
    #
    # Behavior:
    #
    # 1. If a Transition is pending,
    #
    # 1.1. Execute the Transition.
    #
    # 1.2. Return immediately, if %single is true.
    #
    # 2. While not paused and not at end:
    #
    # 2.1. Yield to block, if given.
    #
    # 2.2. If a Transition is pending,
    #
    # 2.2.1. Execute the Transition.
    #
    # 2.2.2. Return immediately, if %single is true.
    #
    # 2.3. Goto 2.
    #
    # Implementation and Semantics:
    #
    # 1) Statemachines cannot be self-recursive, therefore must employ a "transition queue".
    #
    # 2) Statemachines that do not have a queued transition cannot do anything.
    #
    # 3) The queuing of transitions may occur:
    # A) as a side-effect of the entry, doActivity, exit and effect actions (see UML 2 Superstructure for definitions),
    # B) or as stimuli external to the statemachine and it's implied context object.
    #
    # "A" describes what might be called a "synchronous" statemachine: 
    # the statemachine was designed such that it should never pause for external stimulus; 
    # there is always a unambiguous transition that is applicable until the end state is reached.  
    # The statemachine assumes control of the application's execution thread.
    #
    # "B" describes an "asynchronous" statemachine: the statemachine may pause at a state 
    # if there is no queued transition.  
    # The statemachine must not assume control of the application's execution thread,
    # because the application interacts asynchronously with external stimulus:
    # i.e. a human user behind a web browser.
    #
    # In some cases a statemachine may need to be used synchronously and asynchronously 
    # during a single lifetime. 
    #
    # The UML does not specify that a statemachine should or must *always* execute a transition 
    # if a transition is possible.  The consequences are:
    #
    # 1) Machine#run! may not "do" anything, if no transitions were queued.
    # 2) Machine#run! may return before the statemachine reaches the end date.
    #
    # The application or the statemachines's entry, doAction, exit or effect behaviors
    # must explicitly queue a transition, this object will never automatically
    # queue transitions.
    #
    def run! single = false, &blk
      in_run_save = @in_run
      if @in_run
        nil
      else
        @in_run = true
        @paused = false
        process_transitions! single, &blk
      end
    ensure
      @in_run = in_run_save
      @paused = false
    end

    # Alias for run! for who do not read documentation.
    alias :run_pending_transitions! :run!


    # Returns true if run! is executing.
    def running?
      ! ! @in_run
    end


    def paused?
      @paused
    end


    # Causes top-level #run! to return after processing of the active doActivity.
    def pause!
      raise Error, "not in run!" unless @in_run
      @paused = true
    end


    def resume!
      raise Error, "not in run!" unless @in_run
      @paused = false
    end


    # Returns true if current State is processing its :entry behavior.
    def in_entry?
      ! ! @in_entry
    end


    # Returns true if current State is processing its :doActivity behavior.
    def in_doActivity?
      ! ! @in_doActivity
    end


    # Returns true if current State is processing its :exit behavior.
    def in_exit?
      ! ! @in_exit
    end


    # Returns the currently executing Transition.
    def executing_transition
      @executing_transition
    end


    # Returns true if this is executing a Transition.
    def transitioning?
      ! ! @executing_transition
    end


    # Returns true if an executing Transition is processing its :effect behavior.
    def in_effect?
      ! ! @in_effect
    end


    # Forcefully sets state.
    # The State's entry and doActivity are triggered.
    # Any pending transitions triggered in doActivity are queued.
    # Callers should probably call run! after calling this method.
    def state= x
      goto_state! to_state(x)
    end


    # Coerces a String or Symbol to a State.
    # Strings are rooted from the rootStateMachine.
    # Symbols are looked up from this stateMachine.
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
 

    # Coerces a String or Symbol to a Transition.
    # Strings are rooted from the rootStateMachine.
    # Symbols are looked up from this stateMachine.
    def to_transition trans
      case trans
      when trans, nil
        trans
      when String
        stateMachine.rootStateMachine.transition[trans]
      else
        stateMachine.transition[trans]
      end
    end
 

    # Returns true if a transition is possible from the current state.
    # Queries the transitions' guard.
    def guard? *args
      valid_transitions(*args).size > 0
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


    # Returns a list of valid transitions from the current state.
    def valid_transitions *args
      @state.outgoing.select do | t |
        t.guard?(self, args)
      end
    end


    # Find the sole transition whose guard is true and queue it. 
    #
    # If all outgoing transitions' guards are false or more than one 
    # transition's guard is true:
    # raise an error if _raise is true,
    # or return nil.
    def transition_to_next_state!(_raise = true, *args)
      trans = valid_transitions(*args)
      
      if trans.size > 1
        raise Error::AmbiguousTransition, trans.join(', ') if _raise
        return nil
      elsif trans.size != 1
        raise Error::UnknownTransition, state if _raise
        return nil
      end

      queue_transition! trans.first, args
    end


    # Queues transition from current state to another state.
    # This assumes that there is not more than one transition
    # from one state to another.
    def transition_to! state, *args
      state = to_state(state)
      
      trans = transitions_to(state, *args)
      
      case trans.size
      when 0
        raise Error::UnknownTransition, state
      when 1
        queue_transition!(trans.first, args)
      else
        raise Error::AmbiguousTransition, trans.join(', ')
      end
    end


    # Queues a non-ambiguious Transition (see valid_transitions).
    # Returns the Transition queued or nil if no Transition was queued.
    def transition_if_valid! *args
      trans = valid_transitions *args
      trans = trans.size == 1 ? trans.first : nil
      queue_transition!(trans, args) if trans
      trans
    end


    # Queue a Transition from the current State.
    #
    # %trans can be a Transition object or a name pattern.
    #
    # The Transition's guard must be true.
    def transition! trans, *args
      if Transition === trans
        name = trans.name

        _log { "transition! #{name.inspect}" }
        
        trans = nil unless @state === trans.source && trans.guard?(self, args)
      else
        name = trans
        name = name.to_sym unless Symbol === name
        
        _log { "transition! #{name.inspect}" }
        
        # Find a valid outgoing transition.
        trans = @state.outgoing.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          t.guard?(self, args)
        end

        if trans.size > 1
          raise Error::AmbiguousTransition, trans.join(', ')
        end

        trans = trans.first
      end

      if trans
        queue_transition!(trans, args)
      else
        raise Error::CannotTransition, name
      end
    end


    # Converts this object's internal state to a Hash.
    #
    # Some RedSteak objects are coerced to Strings.
    #
    # This representation is ideal for serialization or debugging.
    #
    # context and logger are not represented.
    #
    # History is converted to an Array.
    def to_hash
      h = { }
      instance_variables.each do | k |
        v = instance_variable_get(k)
        k = k.sub(/^@/, '').to_sym unless Symbol === k
        h[k] = v
      end

      h[:state] = (x = h[:state]) && (x.to_s)
      h[:executing_transition] = (x = h[:executing_transition]) && (x.to_s)
      h[:transition_queue] = (x = h[:transition_queue]) && x.to_a.map { | a | a = a.dup; a[0] = a[0].to_s; a }
      history_to_s = [ :previous_state, :new_state, :transition ]
      h[:history] = (x = h[:history]) && x.map do | hh |
        hh = hh.dup
        history_to_s.each do | k |          
          hh[k] = (x = hh[k]) && x.to_s
        end
        hh
      end

      h[:stateMachine] = (x = h[:stateMachine]) && (x.to_s)

      h.delete(:context)
      h.delete(:logger)

      h
    end


    # Restores this object's internal state from a Hash
    # as generated by #to_hash.
    #
    # Assumes that self.stateMachine is already set.
    #
    # History is not restored.
    def from_hash h
      # raise NotImplemented, "from_hash"
      h = h.dup
      h[:state] = to_state(h[:state])
      h[:executing_transition] = to_transition(h[:transition])
      h[:transition_queue] = (x = h[:transition_queue]) && x.to_a.map { | a | a = a.dup; a[0] = to_transition(a[0]); a }
      h.delete(:stateMachine)
      h.delete(:history)
      h.each do | k, v |
        k = "@#{k}" unless Symbol === k
        instance_variable_set(k, v)
      end
      self
    end


    # Returns an Array representation of the state
    # of this Machine.
    def to_a
      x = [ @state && @state.name ]
      x
    end


    def inspect
      "#<#{self.class} #{@stateMachine.name.inspect} #{to_a.inspect}>"
    end


    def _log msg = nil
      return unless @logger
      msg ||= yield
      case 
      when Proc === @logger
        @logger.call(msg)
      when ::IO === @logger
        @logger.puts "#{self.to_s} #{state.to_s} #{msg}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, msg)
      end
    end


    ##################################################################
    # History support
    #


    # Clears current history.
    def clear_history!
      @history && @history.send(@history_clear)
    end

    
    def show_history
      @history.each_with_index{|h, i| puts "#{i + 1}: #{h[:previous_state].to_s} ->  #{h[:new_state].to_s}"}
      ""
    end


    # Records a new history record.
    # Supermachines are also notified.
    # Machine is the origin of the history record.
    def record_history! machine, hash = nil
      if @history
        hash ||= yield
        @history.send(@history_append, hash)
      end

      self
    end


    # Returns true if there are transitions pending.
    def pending_transitions?
      ! @transition_queue.empty?
    end


    private

    # Queues a transition for execution.
    #
    # This prevents recursion into the Machine.
    #
    # This method is guaranteed to return immediately.
    #
    # This method will not cause any entry, doActivity, exit or effect behavior to
    # be executed "now".
    #
    # The #run!, #process_transitions!, and #execute_transition! methods are responsible
    # for executing the transition in the top-level #run! method.
    #
    # UnexpectedRecursion is thrown if entry, exit or effect behaviors are currently active.
    # TransitionPending is thrown if a Transition is already pending.
    #
    def queue_transition! trans, args
      _log { "queue_transition! #{trans.inspect}" }
      if @in_entry || @in_exit || @in_effect
        raise Error::UnexpectedRecursion, "in_entry #{@in_entry.inspect}, in_exit #{@in_exit.inspect}, in_effect #{@in_effect.inspect}"
      end

      unless @transition_queue.empty?
        raise Error::TransitionPending, "#{trans.inspect} when #{transition_queue.inspect} is already pending"
      end

      @transition_queue.clear
      @transition_queue << [ trans, args ]

      # THIS IS A BAD IDEA.
      if @auto_run && ! @in_doActivity
        run!(@auto_run == :single)
      end

      self
    end


    # Processes pending transitions.
    #
    # Returns immediately if #at_end?
    #
    # 1) Process a pending transition and returns immediately after if single.
    # 2) until at_end?
    # 3)   yield to block, if given a block.
    # 4)   If a transition is pending,
    # 5)     execute it and return immediately after if single.
    # 6)   else,
    # 7)     return immediately.
    #
    def process_transitions! single = false
      _log { "process_transitions!" }
      unless at_end?
        # $stderr.puts "  #{__LINE__}"

        # This prevents already queued transitions from accidentally being blown away.
        if (x = @transition_queue.shift)
          # $stderr.puts "  #{__LINE__}"
          execute_transition! *x
          return self if single
        end

        # $stderr.puts "  #{__LINE__}"
        until @paused || at_end?

          # $stderr.puts "  #{__LINE__}"
          yield self if block_given?
          if (x = @transition_queue.shift)
            # $stderr.puts "  #{__LINE__}"
            execute_transition! *x
            break if single
          else
            break
          end
        end
      end

      self
    end


    # Executes transition.
    #
    # 1) self.executing_transition is set.
    # 2) Transition's :effect behavior is performed, while #in_effect? is true.
    # 3) Old State's :exit behavior is performed, while #in_exit? is true.
    # 4) self.executing_transition is unset.
    # 5) Transition history is logged.
    # 6) New State's :entry behavior is performed, while #in_entry? is true.
    # 7) New State's :doActivity behavior is performed, while #in_doActivity? is true.
    #
    # Note: this already assumes that the Transition's guard was true when
    # it was queued.
    def execute_transition! trans, args
      _log { "execute_transition! #{trans.inspect}" }

      raise RedSteak::Error::UnexpectedRecursion, "transition" if @executing_transition

      old_state = @state

      @executing_transition = trans

      # Behavior: Transition effect.
      raise RedSteak::Error::UnexpectedRecursion, "effect" if @in_effect
      @in_effect = true
      _log { "effect! #{trans.inspect}" }
      trans.effect!(self, args)
      @in_effect = false

      # Got to the new state.
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
    ensure
      @executing_transition = nil
      @in_effect = false
    end


    # Moves directly to a State.
    #
    # Calls _goto_state!, clears history and adds initial history record.
    #
    def goto_state! state, args
      _log { "goto_state! #{state.inspect}" }
      _goto_state! state, args do
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
    end


    # Moves from one state machine to another.
    #
    # 1) Performs old State's :exit behavior.
    # 2) If a block is given, yield to it after entering new state.
    # 3) Performs new State's :entry behavior.
    # 4) executing_transition is nil
    # 5) Performs new State's :doActivity behavior.
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
      raise Error::UnexpectedRecursion, "exit" if @in_exit
      @in_exit = true
      if old_state && old_state != state
        (from - to).each do | s |
          _log { "exit! #{s.inspect}" }
          s.exit!(self, args)
        end
      end
      @in_exit = false

      # Move to next state.
      @state = state

      # Yield to block.
      yield if block_given?
      
      # Behavior: entry state.
      raise Error::UnexpectedRecursion, "entry" if @in_entry
      @in_entry = true
      if old_state != state
        (to - from).reverse.each do | s | 
          _log { "entry! #{s.inspect}" }
          s.entry!(self, args)
        end
      end
      @in_entry = false

      # Transition is no longer executing.
      @executing_transition = nil

      # Behavior: doActivity.
      _doActivity!(args)

      self

    rescue Exception => err
      # Revert back to old state.
      @state = old_state

      raise err
    ensure
      # Clear statuses.
      @in_exit = false
      @in_entry = false
      @executing_transition = nil
    end


    # Performs the current State's doActivity while setting a 
    # lock to prevent recursive run!
    # 
    # FIXME?: Should this throw an UnexpectedRecursion if #in_doActivity?
    def _doActivity! args
      _log { "_doActivity! #{args.inspect}" }
      in_doActivity_save = @in_doActivity
      return nil if @in_doActivity
      @in_doActivity = true
      
      @state.doActivity!(self, args)
    ensure
      @in_doActivity = in_doActivity_save
    end

  end # class

end # module


###############################################################################
# EOF
