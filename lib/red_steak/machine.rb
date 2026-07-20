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
  #     def guard() true; end
  #     def effect() ...; end
  #     def entry() ...; end
  #     def doActivity() ...; end
  #     def exit() ...; end
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

    # This object receives Transition and State behavior callbacks:
    #
    # Transition behaviors:
    #
    # * guard(*action)
    # * effect(*action)
    #
    # State behaviors:
    #
    # * entry(*action)
    # * exit(*action)
    # * doActivity(*action)
    #
    # A Transition#guard? may be queried multiple times before
    # a Transition is fired, therefore guards should be free of side-effects.
    attr_accessor :context

    # History of all Transition executions.
    #
    # An collection of Hash objects, each containing:
    # * :time - the Time the Transition was completed.
    # * :transition - the Transition object.
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

    # If not #in_doActivity? AND:
    #
    # 1. If true, queueing a Transition will automatically execute #run!.
    # 2. If :single, queueing a Transition will automatically execute #run!(:single).
    #
    # THIS IS A BAD API IDEA AND MAY GO AWAY SOON!
    attr_accessor :auto_run

    # The queue of events to process.
    attr_reader :event_queue

    # The queue of pending Transition actions.
    attr_reader :action_queue

    # The most recent action.
    attr_reader :action

    # The Transition currently being fired.
    def transition; @action&.transition ; end

    # The trigger that matched the event being processed.
    def trigger;    @action&.trigger    ; end

    # The event currently being processed during the firing of a Transition.
    def event;      @action&.event      ; end

    def initialize opts
      @stateMachine = nil
      @state = nil
      @event_queue = [ ]
      @action_queue = [ ]
      @history = nil
      @history_append = :<<
      @history_clear = :clear
      @auto_run = false
      @in_effect = false
      @in_entry = false
      @in_doActivity = false
      @in_exit = false
      @in_run = false
      @event_id = -1
      @action = nil
      super
    end

    THREAD_KEY = :"::#{self.name}.current"
    def self.current
      Thread.current[THREAD_KEY]
    end
    def self.with_current curr
      save = Thread.current[THREAD_KEY]
      begin
        Thread.current[THREAD_KEY] = curr
        yield curr
      ensure
        Thread.current[THREAD_KEY] = save
      end
    end
    def as_current &blk
      Machine.with_current(self, &blk)
    end

    # Support for Copier.
    def deepen_copy! copier, src
      super
      @event_queue = @event_queue.dup
      @action_queue = @action_queue.dup
      @history = @history && @history.dup
    end

    def _make_action arg
      case arg
      when nil
        Action.new([], @state).validate!
      when Symbol, String
        Action.new([arg.to_sym], @state).validate!
      when Array
        Action.new(arg, @state).validate!
      when Action
        arg.dup.tap{|a| a.state = @state }.validate!
      else
        _raise Error::InvalidValue, "cannot create Action from #{arg.class}"
      end
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
      _raise Error::InvalidValue, "no State #{x.inspect}" unless x
      x.is_a_superstate_of?(@state)
    end

    # Go to the start State.
    #
    # The State's #entry and #doActivity are executed.
    # Any Transitions or events during the State's #doActivity are queued;
    # Queued Transitions are fired only by #run!.
    # #history is not cleared.
    def start! event = nil
      @state = nil
      action = _make_action(event)
      goto_state! @stateMachine.start_state, action
    end

    # Queues an event for #run_events!.
    #
    # Returns self.
    def event! event, run = false
      @event_queue << event
      run_event! if run
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
      while ! @paused && (event = @event_queue.shift)
        run_event! event
        yield self if block_given?
        # Fire the pending transition.
        transition_fired = run!(:single, &blk)
      end
      transition_fired
    end

    def run_event! event = nil
      event ||= @event_queue.shift
      return if ! event
      _log { "event #{event.inspect}" }
      action = _make_action(event)
      actions = _matching_transitions(action, 2)
      binding.pry if event == [:lift_receiver]
      _queue_action!(_transition_arity!(action, actions))
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
    # The application or the statemachines' entry, doAction, exit or effect behaviors
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
      _raise Error::NotRunning, "not in run!" unless @in_run
      @paused = true
    end

    # Allows #run! to continue if #pause! was called during #run!.
    def resume!
      _raise Error::NotRunning, "not in run!" unless @in_run
      @paused = false
    end

    # Returns true if the active State#entry is running.
    def in_entry?
      ! ! @in_entry
    end

    # Returns true if the active State#doActivity is running.
    def in_doActivity?
      ! ! @in_doActivityƒ
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
    def to_state x
      case state
      when Symbol
        stateMachine.state[x]
      when String
        stateMachine.rootStateMachine.state[x]
      when State, nil
        x
      when Action
        x.state or _raise Error::InvalidValue, "to_state: #{x.class}"
      else
        _raise Error::InvalidValue, "to_state: #{x.class}"
      end
    end

    # Coerces a String or Symbol to a Transition.
    # Strings are rooted from the #rootStateMachine.
    # Symbols are looked up from #stateMachine.
    def to_transition x
      case x
      when Symbol
        stateMachine.transition[x]
      when String
        stateMachine.rootStateMachine.transition[x]
      when Transition, nil
        x
      when Action
        x.transition or _raise Error::InvalidValue, "to_transition: #{x.class}"
      else
        _raise Error::InvalidValue, "to_transition: #{x.class}"
      end
    end

    # Returns true if a Transition is possible from the active #state.
    # Queries the Transition#guard.
    def guard? event = nil
      action = _make_action(event)
      valid_transitions(action).size > 0
    end

    # Returns true if a non-ambiguous direct Transition is possible from the active #state
    # to the given State.
    # Uses #transitions_to.
    def can_transition_to? state, event = nil
      action = _make_action(event)
      transitions_to(state, action).size == 1
    end

    # Returns an Enumeration of valid Transitions from active
    # #state to the specified State where Transition#guard? is true.
    def transitions_to state, event = nil
      state = to_state(state)
      action = _make_action(event)
      @state.outgoing.select do | t |
        t.target == state && (action.transition = t) && _guard?(action)
      end
    end

    # Returns an Enumeration of valid Transitions from active
    # #state to the specified State where Transition#guard? is true.
    def transitions_from state, event = nil
      state = to_state(state)
      action = _make_action(event)
      state.outgoing.select do | t |
        action.transition = t
        _guard?(action)
      end
    end

    # Returns an Enumeration of valid Transitions from the active State
    # where Transition#guard? is true.
    def valid_transitions event = nil
      transitions_from @state, event
    end

    # Find the sole Transition whose Transition#guard? is true and queue it.
    #
    # If all outgoing Transitions#guard? are false or more than one
    # #transition#guard? is true:
    # raise an Error::TooManyTransitions or Error::UnknownTransition error if _raise_error_ is true,
    # or return nil.
    def transition_to_next_state!(raise_error = true, event = nil)
      action = _make_action(event)
      actions = _matching_transitions(action)
      _transition_arity!(action, actions)
      _queue_action! actions.first
    end

    # Queues a non-ambiguous Transition (see #valid_transitions).
    # Returns the Transition queued or nil if no Transition was queued.
    def transition_if_valid! event = nil
      action = _make_action(event)
      actions = _matching_transitions(action)
      _queue_action! actions.first if actions.size == 1
    end

    # Queues Transition from active #state to another State.
    # This requires that there is not more than one valid Transition
    # from one State to another.
    # The Transition#guard? must be true.
    def transition_to! state, event = nil
      state = to_state(state)
      action = _make_action(event)
      actions = _matching_transitions(action).select{|a| a.state == state }
      _transition_arity!(action, actions)
      _queue_action! actions.first
    end

    # Queue a Transition from the active #state.
    # _trans_ can be a Transition object or a name pattern.
    # The Transition#guard? must be true.
    def transition! trans, event = nil
      action = _make_action(event)
      case trans
      when Transition
        _log { "transition! #{trans.name.inspect}" }
        transitions = (
          @state === trans.source && (action.transition = trans) && _guard?(action)
        ) ? [ trans ] : EMPTY_ARRAY
      when Symbol, String
        name = trans.to_sym
        _log { "transition! #{name.inspect}" }
        # Find a matching outgoing transition.
        transitions = @state.outgoing.select do | t |
          t === name && _guard?(t, action)
        end.map
      else
        raise Error::InvalidValue, "transition! unexpected #{trans.class}"
      end
      action.transition = _transition_arity!(action, transitions)
      _queue_action! action
    end

    ##################################################################

    # Returns the Actions that match the event.
    # This searches up the State#ancestors (including the current State)
    # for a matching Transition.
    def _matching_transitions action, limit = nil
      result = [ ]
      action.state.ancestors.each do | s |
        s.outgoing.each do | trans |
          a = action.dup.tap{|a| a.transition = trans}
          # a.validate!
          if (trigger = trans.matches_event?(a.event)) && _guard?(a)
            a.trigger = trigger
            result << action
            return result if limit && result.size >= limit
          end
        end
      end
      result
    end

    def _transition_arity! action, actions, msg = "transition"
      case actions.size
      when 1
        yield actions.first
      when 0
        _raise Error::NoTransitions, msg, state: action.state, event: action.event
      else
        _raise Error::TooManyTransitions, msg, state: action.state, event: action.event, transitions: actions.map(&:transition)
      end
      actions.first
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
      h[:action_queue] = (x = h.delete(action_queue)) && x.to_a.map do | a |
        [ a.transition.to_a ]
      end
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
      # _raise Error::NotImplemented, :from_hash
      h = h.dup
      h[:state] = to_state(h[:state])
      h[:transition] = to_transition(h[:transition])
      h[:action_queue] = (x = h[:action_queue]) && x.to_a.map do | a |
        Action.new(h[:state], to_transition(a[0]), a[1..-1])
      end
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
    # the #action_queue.
    def pending_transitions?
      ! @action_queue.empty?
    end

    private

    def _guard? action
      # pp(action: action)
      _log { "guard? #{action.inspect} => #{action.transition.guard.inspect}" }
      action.transition.guard?(action)
    end

    # Queues a Transition action for execution.
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
    def _queue_action! action
      _typecheck! Action, action
      action.validate!
      @event_id += 1
      _log { "__queue_action! #{action.transition.inspect}" }
      if @in_entry || @in_exit || @in_effect
        _raise Error::UnexpectedRecursion, :_queue_action!,
          :state => action.state,
          :transition => action.transition,
          :in_entry => @in_entry,
          :in_exit => @in_exit,
          :in_effect => @in_effect
      end

      unless @action_queue.empty?
        _raise Error::TransitionPending, :_queue_action!,
          :state => action.state,
          :transition => action.transition,
          :action_queue => action_queue.dup
      end

      @action_queue.clear
      action.machine = nil #
      @action_queue << action

      # THIS IS A BAD IDEA.
      if @auto_run && ! @in_doActivity
        run!(@auto_run == :single)
      end

      action.transition
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
        # This prevents already queued transitions from accidentally being blown away.
        if (action = @action_queue.shift)
          _fire_transition! action
          return self if single
        end
        until @paused || at_end?
          yield self if block_given?
          if (action = @action_queue.shift)
            _fire_transition! action
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
    def _fire_transition! action
      # pp(action: action)
      action.machine = self
      @action = action
      binding.pry unless Action === action
      _typecheck! Action, action
      @event_id += 1
      _log { "_fire_transition! #{action.inspect}" }
      begin
        @transition = trans = action.transition
        binding.pry unless Transition === trans
        raise unless action.state == @state
        _typecheck! Transition, trans
        # @transition = trans
        # @trigger = action.trigger
        # @event = event
        action.machine = self
        @in_effect = true
        _log { "effect! #{trans.inspect} => #{trans.effect.inspect}" }
        trans.effect!(action)
        @in_effect = false
        # Go to the new state.
        old_state = @state # action.state
        action.state = trans.target
        _goto_state!(action) do
          record_history! do
            {
              :time => Time.now.gmtime,
              :previous_state => old_state,
              :transition => action.transition,
              :new_state => action.state,
              :event => action.event,
              :trigger => action.trigger,
            }
          end
        end
        self
      ensure
        @action = action.machine = nil
        @in_effect = false
      end
    end

    # Moves directly to a State.
    #
    # Calls #_goto_state!, clears #history and records initial #history record.
    #
    def goto_state! state, event = nil
      action = _make_action(event)
      action.state = state
      _log { "goto_state! #{action.state.inspect}" }
      _goto_state!(action) do
        clear_history!
        record_history! do
          {
            :time => Time.now.gmtime,
            :previous_state => nil,
            :transition => nil,
            :new_state => @state,
            :event => action.event,
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
    def _goto_state! action
      # pp(action: action)
      action.machine = self
      @action = action
      @event_id += 1
      old_state = @state
      new_state = action.state or raise

      # If the state has a submachine,
      # start! it.
      while ssm = new_state.submachine
        if ss = ssm.start_state
          new_state = ssm.start_state
        end
      end

      from  = old_state ? old_state.ancestors : EMPTY_ARRAY
      to    = new_state ? new_state.ancestors : EMPTY_ARRAY
      trans = action.transition

      from_event = action.dup # .tap{|a| a.machine = self }
      to_event   = action.dup # .tap{|a| a.machine = self }

      if old_state == nil && false
        pp(old_state: old_state, new_state: new_state)
        pp(to: to, from: from)
        binding.pry
      end

      # Behavior: exit state.
      _raise Error::UnexpectedRecursion, :exit if @in_exit
      @in_exit = true
      if old_state && old_state != new_state
        if ! trans || trans.kind != :internal
          (from - to).each do | s |
            @event_id += 1
            from_event.state = s
            _log { "exit! #{s.inspect} => #{s.exit.inspect}" }
            s.exit!(from_event)
          end
        end
      end
      @in_exit = false

      # Move to next state.
      @state = new_state

      begin
        # Yield to block.
        yield if block_given?

        # Behavior: entry state.
        _raise Error::UnexpectedRecursion, :entry if @in_entry
        @in_entry = true
        if old_state != new_state
          if ! trans || trans.kind != :internal
            (to - from).reverse_each do | s |
              @event_id += 1
              to_event.state = s
              _log { "entry! #{s.inspect} => #{s.entry.inspect}" }
              s.entry!(to_event)
            end
          end
        end
        @in_entry = false

        # Behavior: doActivity.
        @event_id += 1
        _raise Error::UnexpectedRecursion, :doActivity if @in_doActivity
        @in_doActivity = true
        to_event.state = new_state
        @state.doActivity!(to_event)
        @in_doActivity = false

        self
      rescue Exception => err
        # Revert back to old state.
        @state = old_state
        raise err
      end
    ensure
      # Clear statuses.
      @in_exit = @in_entry = @in_doActivity = false
      @action = action.machine = nil
    end

    def _raise cls, msg, opts = { }
      if cls.ancestors.include?(Error)
        opts[:message] = msg.to_s
        opts[:machine] = self
        opts[:state] ||= @state
        opts[:event] ||= @action&.event
        opts[:transition] ||= @action&.transition
        opts[:context] ||= @context
        opts[:event_id] ||= @event_id
      else
        if opts.empty?
          opts = msg.to_s
        else
          opts = "#{msg} #{opts.inspect}"
        end
      end
      pp [ cls, opts ] if @verbose
      raise cls, opts
    end
  end
end
