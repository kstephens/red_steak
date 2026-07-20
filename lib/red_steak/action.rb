require 'red_steak'

module RedSteak
  class Action < Struct.new(:event, :state, :transition, :trigger)
    def event_type; event.first; end
    def context; machine.context; end

    def validate!
      raise Error::InvalidValue, "state #{state.class}"           unless state.nil? || State === state
      raise Error::InvalidValue, "transition #{transition.class}" unless transition.nil? || Transition === transition
      self
    end

    THREAD_KEY = :"::#{self.name}.current"
    def self.current
      Thread.current[THREAD_KEY]
    end
    def self.with_current curr
      save = Thread.current[THREAD_KEY]
      begin
        Thread.current[THREAD_KEY] = curr
        Machine.with_current(curr.machine) do
          yield curr
        end
      ensure
        Thread.current[THREAD_KEY] = save
      end
    end
    def as_current &blk
      Action.with_current(self, &blk)
    end
  end
end
