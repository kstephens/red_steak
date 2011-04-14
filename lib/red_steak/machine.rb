# require 'debug'

require 'red_steak'

module RedSteak
  # Machine manages the execution semantics of a StateMachine during the triggering a Transition between
  # the source State and the target State objects of a StateMachine.
  #
  # Features:
  #
  # * It can record Transition history.
  # * Multiple instances can "walk" the same StateMachine.
  # * Instances are easily serialized using Marshal.
  #
  # Example:
  #
  #   sm = RedSteak::Builder.new.build do
  #     statemachine :my_sm do 
  #       initial :start
  #       final :end
  #
  #       state :start
  #       transition :a #, :name => :'start->a'
  #
  #       state :a
  #       transition :b, :name => :a_b
  #       transition :c # a->c
  #
  #       state :b
  #       transition :c
  #       transition :end
  #
  #       state :c
  #       transition :b
  #       transition :end
  #
  #       state :end
  #     end
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
  #   m.transition!(:'start->a')
  #   m.run!(:single)
  #   m.transition!(:ab)
  #   m.run!(:single)
  #   m.transition!(:'b->end')
  #   m.run!(:single)
  #   m.at_end? # => true
  #   
  class Machine < Base
    # The StateMachine.
    attr_accessor :stateMachine # UML
    alias :statemachine :stateMachine # not UML

    # The active leaf State in the statemachine.
    # See #state_is_active?(State) to query for superstates.
    attr_reader :state

    # True if #pause! was called during #run!
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
    # A Transition#guard? may be queried multiple times before
    # a Transition is fired, therefore guards should be free of side-effects.
    attr_accessor :context

    # History of all Transition executions.
    #
    # An collection of Hash objects, each containing:
    # * :time - the Time the Transition was completed.
    # * :transition - the Transtion object.
    # * :previous_state - the State before the Transition.
    # * :new_state - the State after the Transition.
    # * :event - the #event being processed during the Transition.
    # 
    # #start! will create an initial #history entry 
    # where :transition and :previous_state is nil.
    #
    attr_accessor :history

    # A Hash to merge into each history record.
    # Defaults to nil.
    # Useful for logging additional information for each transition,
    # such as the HTTP request params for an event in a web application.
    attr_accessor :history_data

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

    # If not #in_doActivity? AND:
    #
    # 1. If true, queueing a Transition will automatically execute #run!.
    # 2. If :single, queueing a Transition will automatically execute #run!(:single).
    #
    # THIS IS A BAD API IDEA AND MAY GO AWAY SOON!
    attr_accessor :auto_run

    # The queue of events to process.
    attr_reader :event_queue

    # The queue of pending Transitions.
    attr_reader :transition_queue

    # The Transition currently being fired.
    attr_reader :transition

    # The last Transition fired;
    # Useful during a State#doAction after the firing of Transition.
    attr_reader :last_transition

    # The event currently being processed during the firing of a Transition.
    attr_reader :event

    # The trigger that matched the event being processed.
    attr_reader :trigger

    
    def initialize opts
      @stateMachine = nil
      @state = nil
      @event_queue = [ ]
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
      @transition = nil
      @event = nil
      @trigger = nil

      super
    end
    

    # Support for Copier.
    def deepen_copy! copier, src
      super
      @event_queue = @event_queue.dup
      @transition_queue = @transition_queue.dup
      @history = @history && @history.dup
    end

 
    # Returns true if #start! has been called.
    def started?
      ! @state.nil?
    end


    # Returns true if we are at the start State.
    def at_start?
      @state == @stateMachine.start_state
    end


    # Returns true if we are at the end State (FinalState).
    def at_end?
      FinalState === @state || # UML
      @state == @stateMachine.end_state # not UML
    end


    # Returns true if State _s_ is active.
    # This is true if _s_ an superstate ancestor of the active leaf state.
    def state_is_active? s
      return false unless s && @state
      x = to_state(s)
      return ArgumentError, "no State #{x.inspect}" unless x
      x.is_a_superstate_of?(@state)
    end


    # Go to the start State.
    #
    # The State's #entry and #doActivity are executed.
    # Any Transitions or events during the State's #doActivity are queued;
    # Queued Transitions are fired only by #run!.
    # #history is not cleared.
    def start! *args
      @state = nil
      goto_state! @stateMachine.start_state, args
    end


    # Queues an event for #run_events!.
    #
    # _event_ is an Array containing a Symbol at the beginning, 
    # with subsequent elements representing the event's arguments.
    #
    # A lone Symbol is coerced to an Array as decribed above.
    #
    # The Array is frozen before placing it in the event queue.
    #
    # Returns self.
    #
    def event! event
      case event
      when Array
      when Symbol
        event = [ event ]
      else
        raise ArgumentError, "expected Array or Symbol, given #{event.class}"
      end
      event.freeze
      @event_queue << event
      self
    end


    # Runs events until there are no events in the event queue or #paused?
    #
    # #event is set to the event during its processing.
    #
    # Returns the last Transition fired.
    #
    # The Machine will respond to an event with different Transitions
    # depending on the current State and the outgoing Transitions' guards 
    # and fire the unique Transition that matches.  
    # 
    # The event abstracts the interaction between the context and Transtions.
    #
    # Transitions have 0..* Triggers (which are ruby Symbols)
    # which match the first element of an event; an Array with a Symbol at the
    # front representing the method selector.
    # 
    # An event represents a message.  A good design principal is to queue an
    # event in the Machine at the end of a method in the context.
    #
    # Events are queued in the Machine with #event!(e). 
    #
    # #run_event! executes events until the event queue is empty or until
    # pause! is called.
    #
    # Machine#run_event! takes an event from the
    # event queue, and finds the first singular Transition that has a Trigger that
    # matches the event *and* has a guard that evaluates as true.  
    #
    # The Transition is queued and #run!(:single) is called.
    # 
    # A block given to #run_events! is passed to #run!.
    #
    def run_events! &blk
      transition_fired = nil
      @paused = false
      while ! @paused && (@event = @event_queue.shift) 
        _log { "event #{event.inspect}" }
        t = transitions_matching_event(@event)
        case t.size
        when 0
          _raise Error::UnhandledEvent, "No transitions for event",
          :event => @event
        when 1
          event_args = event.size > 1 ? @event[1 .. -1] : EMPTY_ARRAY
          transition_fired, @trigger = *t.first
          queue_transition! transition_fired, event_args
        else
          _raise Error::UnhandledEvent, "Too many transititons for event",
          :event => @event,
          :transitions => t # .map { | x | [ x[0].to_uml_s, x[1] ] }
        end

        yield self if block_given?

        # Fire the pending transition.
        run!(:single, &blk)
      end

      transition_fired

    ensure
      @event = nil
      @trigger = nil
    end


    # Returns the Transitions and Triggers that match the event.
    # This searches up the State#ancestors (including the current State)
    # for a matching Transition.
    def transitions_matching_event event, state = nil, limit = nil
      state ||= @state
      event_args = event[1 .. -1]
      result = [ ]
      state.ancestors.each do | s |
        s.outgoing.each do | trans |
          if (trigger = trans.matches_event?(event)) &&
              _guard?(trans, event_args) 
            result << [ trans, trigger ]
            break if limit && result.size >= limit
          end
        end
      end
      result
    end


    # Run pending transitions.
    # 
    # Only the top-level #run! will process pending transitions,
    # #run! has no effect if called recursively, i.e. from a State #doActivity or Transition #effect.
    # Returns self if #run! is at the top-level, nil if a #run! is already active.
    #
    # If _single_ is true, only one Transition is fired.
    #
    # Behavior:
    #
    # 1. If a Transition is pending,
    # 1.1. Fire the Transition.
    # 1.2. Return immediately, if _single_ is true.
    # 2. While not paused and not at end:
    # 2.1. Yield to block, if given.
    # 2.2. If a Transition is pending,
    # 2.2.1. Fire the Transition.
    # 2.2.2. Return immediately, if _single_ is true.
    # 2.3. Goto 2.
    #
    # Implementation and Semantics:
    #
    # 1. Statemachines cannot be self-recursive, therefore must employ a "transition queue".
    # 2. Statemachines that do not have a queued transition cannot do anything.
    # 3. The queuing of transitions may occur:
    # 3.1. as a side-effect of the entry, doActivity, exit and effect actions (see UML 2 Superstructure for definitions),
    # 3.2. or as stimuli external to the statemachine and it's implied context object.
    #
    # "3.1." describes what might be called a "synchronous" statemachine: 
    # the statemachine was designed such that it should never pause for external stimulus; 
    # there is always a unambiguous transition that is applicable until the end state is reached.  
    # The statemachine assumes control of the application's execution thread.
    #
    # "3.2." describes an "asynchronous" statemachine: the statemachine may pause at a state 
    # if there is no queued transition.  
    # The statemachine must not assume control of the application's execution thread,
    # because the application interacts asynchronously with external stimulus:
    # i.e. a human user behind a web browser.
    #
    # In some cases a statemachine may need to be used synchronously and asynchronously 
    # during a single lifetime. 
    #
    # The UML does not specify that a statemachine should or must *always* fire a transition 
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


    # Returns true if #run! is executing.
    def running?
      ! ! @in_run
    end


    # Returns true if #pause! was called during #run!.
    def paused?
      @paused
    end


    # Causes top-level #run! to return after the active #doActivity.
    def pause!
      _raise Error, "not in run!" unless @in_run
      @paused = true
    end


    # Allows #run! to continue if #pause! was called during #run!.
    def resume!
      _raise Error, "not in run!" unless @in_run
      @paused = false
    end


    # Returns true if the active State#entry is running.
    def in_entry?
      ! ! @in_entry
    end


    # Returns true if the active State#doActivity is running.
    def in_doActivity?
      ! ! @in_doActivity
    end


    # Returns true if the active State#exit is running.
    def in_exit?
      ! ! @in_exit
    end


    # Returns true if a Transition is executing.
    # New Transitions cannot be queued while this is true.
    def transitioning?
      ! ! @transition
    end


    # Returns true if an executing Transition#effect is running.
    # New Transitions cannot be queued while this is true.
    def in_effect?
      ! ! @in_effect
    end


    # Forcefully sets #state.
    # The State#entry and State#doActivity are executed.
    # Any pending Transitions triggered in State#doActivity are queued.
    # Callers should probably call #run! after calling this method.
    # See #goto_state!.
    def state= x
      goto_state! to_state(x)
    end


    # Coerces a String or Symbol to a State.
    # Strings are rooted from the rootStateMachine.
    # Symbols are looked up from #stateMachine.
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
    # Strings are rooted from the #rootStateMachine.
    # Symbols are looked up from #stateMachine.
    def to_transition trans
      case trans
      when Transition, nil
        trans
      when String
        stateMachine.rootStateMachine.transition[trans]
      else
        stateMachine.transition[trans]
      end
    end
 

    # Returns true if a Transition is possible from the active #state.
    # Queries the Transition#guard.
    def guard? *args
      valid_transitions(*args).size > 0
    end


    # Returns true if a non-ambigious direct Transition is possible from the active #state
    # to the given State.
    # Uses #transitions_to.
    def can_transition_to? state, *args
      transitions_to(state, *args).size == 1
    end


    # Returns an Enumeration of valid Transitions from active
    # #state to the specified State where Transition#guard? is true.
    def transitions_to state, *args
      state = to_state(state)

      trans = @state.outgoing.select do | t |
        t.target == state &&
          _guard?(t, args)
      end

      trans
    end


    # Returns an Enumeration of valid Transitions from the active State
    # where Transition#guard? is true.
    def valid_transitions *args
      @state.outgoing.select do | t |
        _guard?(t, args)
      end
    end


    # Find the sole Transition whose Transition#guard? is true and queue it. 
    #
    # If all outgoing Transitions#guard? are false or more than one 
    # #transition#guard? is true:
    # raise an Error::AmbiguousTransition or Error::UnknownTransition error if _raise_error_ is true,
    # or return nil.
    def transition_to_next_state!(raise_error = true, *args)
      trans = valid_transitions(*args)
      
      if trans.size > 1
        _raise Error::AmbiguousTransition, :transition_to_next_state!, :transitions => trans if raise_error
        return nil
      elsif trans.size != 1
        _raise Error::UnknownTransition, :transition_to_next_state!, :state => state if raise_error
        return nil
      end

      queue_transition! trans.first, args
    end


    # Queues Transition from active #state to another State.
    # This requires that there is not more than one valid Transition
    # from one State to another.
    def transition_to! state, *args
      state = to_state(state)
      
      trans = transitions_to(state, *args)
      
      case trans.size
      when 0
        _raise Error::UnknownTransition, :transition_to!, :state => state
      when 1
        queue_transition!(trans.first, args)
      else
        _raise Error::AmbiguousTransition, :transition_to!, :transitions => trans
      end
    end


    # Queues a non-ambiguious Transition (see #valid_transitions).
    # Returns the Transition queued or nil if no Transition was queued.
    def transition_if_valid! *args
      trans = valid_transitions *args
      trans = trans.size == 1 ? trans.first : nil
      queue_transition!(trans, args) if trans
      trans
    end


    # Queue a Transition from the active #state.
    #
    # _trans_ can be a Transition object or a name pattern.
    #
    # The Transition#guard? must be true.
    def transition! trans, *args
      if Transition === trans
        name = trans.name

        _log { "transition! #{name.inspect}" }
        
        trans = nil unless @state === trans.source && _guard?(trans, args)
      else
        name = trans
        name = name.to_sym
        
        _log { "transition! #{name.inspect}" }
        
        # Find a valid outgoing transition.
        trans = @state.outgoing.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          _guard?(t, args)
        end

        if trans.size > 1
          _raise Error::AmbiguousTransition, :transition!, :transitions => trans
        end

        trans = trans.first
      end

      if trans
        queue_transition!(trans, args)
      else
        _raise Error::CannotTransition, :transition!, :transition_name => name
      end
    end


    # Converts this object's internal state to a Hash.
    #
    # Some RedSteak objects are coerced to Strings.
    #
    # This representation is ideal for serialization or debugging.
    #
    # #context and #logger are not represented.
    #
    # #history is converted to an Array of simple Hash objects.
    def to_hash
      h = { }
      instance_variables.each do | k |
        v = instance_variable_get(k)
        k = k.sub(/^@/, '').to_sym unless Symbol === k
        h[k] = v
      end

      h[:state] = (x = h[:state]) && (x.to_s)
      h[:transition] = (x = h[:transition]) && (x.to_s)
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
    # Assumes that #stateMachine is already set.
    #
    # #history is not restored.
    def from_hash h
      # _raise NotImplemented, :from_hash
      h = h.dup
      h[:state] = to_state(h[:state])
      h[:transition] = to_transition(h[:transition])
      h[:transition_queue] = (x = h[:transition_queue]) && x.to_a.map { | a | a = a.dup; a[0] = to_transition(a[0]); a }
      h.delete(:stateMachine)
      h.delete(:history)
      h.each do | k, v |
        k = "@#{k}" unless Symbol === k
        instance_variable_set(k, v)
      end
      self
    end


    # Returns an Array representation of the #state
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
      case 
      when Proc === @logger
        msg ||= yield
        @logger.call(msg)
      when ::IO === @logger
        msg ||= yield
        @logger.puts "#{self.to_s} #{state.to_s} #{msg}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug) { msg ||= yield }
      end
    end


    ##################################################################
    # History support
    #


    # Clears #history.
    def clear_history!
      @history && @history.send(@history_clear)
      self
    end

    
    # Prints #history on the _out_ stream.
    def show_history out = $stdout
      @history.each_with_index{|h, i| out.puts "#{i + 1}: #{h[:previous_state].to_s} -> #{h[:new_state].to_s}"}
      ""
    end


    # Records a new #history record.
    # #history_data is added to the history record, if not nil.
    def record_history! hash = nil
      if @history
        hash ||= yield
        hash.update(@history_data) if @history_data
        @history.send(@history_append, hash)
      end

      self
    end


    # Returns true if there is a Transition pending in
    # the #transition_queue.
    def pending_transitions?
      ! @transition_queue.empty?
    end


    ##################################################################
    # PRIVATE
    #

    private

    def _guard? t, args
      _log { "guard? #{t.inspect} => #{t.guard.inspect}" }
      t.guard?(self, args)
    end

    # Queues a Transition for execution.
    #
    # This prevents recursion into the Machine.
    #
    # This method is guaranteed to return immediately.
    #
    # This method will not cause any State#entry, State#doActivity, State#exit or Transition#effect behavior to
    # be executed "now".
    #
    # The #run!, #process_transitions!, and #fire_transition! methods are responsible
    # for firing the transition in the top-level #run! method.
    #
    # UnexpectedRecursion is thrown if State#entry, State#exit or Transition#effect behaviors are executing.
    # TransitionPending is thrown if a Transition is already pending.
    #
    # Note: this method already assumes that the Transition#guard? was true before
    # it is queueing; guards are not checked here, nor are they checked again.
    #
    def queue_transition! trans, args
      _log { "queue_transition! #{trans.inspect}" }
      if @in_entry || @in_exit || @in_effect
        _raise Error::UnexpectedRecursion, :queue_transition, 
          :in_entry => @in_entry, 
          :in_exit => @in_exit, 
          :in_effect => @in_effect
      end

      unless @transition_queue.empty?
        _raise Error::TransitionPending, :queue_transition!,
          :transition => trans,
          :transition_queue => transition_queue.dup
      end

      @transition_queue.clear
      @transition_queue << [ trans, args ]

      # THIS IS A BAD IDEA.
      if @auto_run && ! @in_doActivity
        run!(@auto_run == :single)
      end

      self
    end


    # Processes queued Transitions.
    #
    # Returns immediately if #at_end?
    #
    # 1) Process a pending Transition and returns immediately after if _single_.
    # 2) until at_end?
    # 3)   yield to block, if given a block.
    # 4)   If a Transition is pending,
    # 5)     fire it and return immediately after if _single_.
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
          fire_transition! *x
          return self if single
        end

        # $stderr.puts "  #{__LINE__}"
        until @paused || at_end?

          # $stderr.puts "  #{__LINE__}"
          yield self if block_given?
          if (x = @transition_queue.shift)
            # $stderr.puts "  #{__LINE__}"
            fire_transition! *x
            break if single
          else
            break
          end
        end
      end

      self
    end


    # Fires a Transition.
    #
    # * #transition is set.
    # * Transition#effect behavior is performed, while #in_effect? is true.
    # * #_goto_state(Transition#target) is performed with #record_history!.
    #
    # Note: this method already assumes that the Transition#guard? was true when
    # it was queued; guards are not checked here.
    def fire_transition! trans, args
      _log { "fire_transition! #{trans.inspect}" }

      _raise Error::UnexpectedRecursion, :transition if @transition

      old_state = @state

      @transition = trans

      # Behavior: Transition effect.
      _raise Error::UnexpectedRecursion, :effect if @in_effect
      @in_effect = true
      _log { "effect! #{trans.inspect} => #{trans.effect.inspect}" }
      trans.effect!(self, args)
      @in_effect = false

      # Go to the new state.
      _goto_state!(trans.target, trans, args) do 
        record_history! do 
          {
            :time => Time.now.gmtime,
            :previous_state => old_state, 
            :transition => trans, 
            :new_state => state,
            :event => @event,
            :trigger => @trigger,
          }
        end
      end

      self
    ensure
      @transition = nil
      @in_effect = false
    end


    # Moves directly to a State.
    #
    # Calls #_goto_state!, clears #history and records initial #history record.
    #
    def goto_state! state, args
      _log { "goto_state! #{state.inspect}" }
      _goto_state! state, nil, args do
        clear_history!
        record_history! do 
          {
            :time => Time.now.gmtime,
            :previous_state => nil, 
            :transition => nil, 
            :new_state => @state,
          }
        end
      end
    end


    # Moves from one State to another.
    #
    # * If the Transition#target State #is_composite?, the innermost submachine's state State is the actual target.
    # * The old source State#exit behavior(s) are performed for all superstates that are to become inactive, while #in_exit? is true.
    # * #transition is unset.
    # * Transition history is logged.
    # * The new target State#entry behavior(s) are performed for all substates that are to become active,, while #in_entry? is true.
    # * The new target State#doActivity behavior is performed while #in_doActivity? is true.
    #
    def _goto_state! state, trans, args
      old_state = @state

      # If the state has a submachine,
      # start! it.
      while ssm = state.submachine
        if ss = ssm.start_state
          state = ssm.start_state
        end
      end

      from = old_state ? old_state.ancestors : EMPTY_ARRAY
      to = state ? state.ancestors : EMPTY_ARRAY

      # Behavior: exit state.
      _raise Error::UnexpectedRecursion, :exit if @in_exit
      @in_exit = true
      if old_state && old_state != state
        (from - to).each do | s |
          if ! trans || trans.kind != :internal
            _log { "exit! #{s.inspect} => #{s.exit.inspect}" }
            s.exit!(self, args)
          end
        end
      end
      @in_exit = false

      # Move to next state.
      @state = state

      # Yield to block.
      yield if block_given?
      
      # Behavior: entry state.
      _raise Error::UnexpectedRecursion, :entry if @in_entry
      @in_entry = true
      if old_state != state
        (to - from).reverse_each do | s | 
          if ! trans || trans.kind != :internal
            _log { "entry! #{s.inspect} => #{s.entry.inspect}" }
            s.entry!(self, args)
          end
        end
      end
      @in_entry = false

      # Transition is fired.
      @last_transition = @transition
      @transition = nil

      # Behavior: doActivity.
      _raise Error::UnexpectedRecursion, :doActivity if @in_doActivity
      @in_doActivity = true
      @state.doActivity!(self, args)
      @in_doActivity = false

      self

    rescue Exception => err
      # Revert back to old state.
      @state = old_state

      raise err

    ensure
      # Clear statuses.
      @in_exit = false
      @in_entry = false
      @in_doActivity = false
      @transition = nil
    end


    def _raise cls, msg, opts = { }
      if cls.ancestors.include?(Error)
        opts[:message] = msg.to_s
        opts[:machine] = self
        opts[:state] = @state
      else
        if opts.empty?
          opts = msg.to_s
        else
          opts = "#{msg} #{opts.inspect}"
        end
      end
      # pp [ cls, opts ]
      raise cls, opts
    end

  end # class

end # module


###############################################################################
# EOF
