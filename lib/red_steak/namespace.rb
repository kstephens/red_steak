
module RedSteak

  # A Namespace object.
  class Namespace < NamedElement

    # List of all Vertex object: States and Pseudostates.
    attr_reader :ownedMember


    def initialize opts
      @ownedMember = NamedArray.new([ ], :ownedMember)
      super
    end
    

    def deepen_copy! copier, src
      super

      @ownedMember = copier[@ownedMember]
    end


    # Returns the outer-most Namespace
    def rootNamespace
      @namespace ? @namespace.rootNamespace : self
    end


    def add_ownedMember! m
      _log "add_ownedMember! #{m.inspect}"

      if @ownedMember.find { | x | x.class == m.class && x.name == m.name }
        raise ArgumentError, "object named #{m.name.inspect} already exists"
      end

      @ownedMember << m
      m.namespace = self

      # Notify.
      m.ownedMember_added! self

      m
    end


    def remove_ownedMember! m
      _log "remove_ownedMember! #{m.inspect}"

      @ownedMember.delete(m)
      m.namespace = nil

      # Notify.
      m.ownedMember_removed! self

      self
    end


    ##################################################################


    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.to_a.inspect} #{(state && state.to_a).inspect} #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, *args)
      when (x = @namespace)
        x._log *args
      end
    end



  end # class

end # module


###############################################################################
# EOF
