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

    def freeze
      return self if frozen?
      @ownedMember.freeze
      super
    end

    # Returns the outer-most Namespace
    def rootNamespace # UML
      @namespace ? @namespace.rootNamespace : self
    end
    alias :root_namespace :rootNamespace # NOT UML

    def add_ownedMember! m
      _log { "add_ownedMember! #{m.inspect}" }
      @ownedMember.check_name_conflict! :add_ownedMember!, m, :verify_class
      @ownedMember << m
      m.namespace = self
      # Notify.
      m.ownedMember_added! self
      m
    end

    def remove_ownedMember! m
      _log { "remove_ownedMember! #{m.inspect}" }
      @ownedMember.delete(m)
      m.namespace = nil
      # Notify.
      m.ownedMember_removed! self
      self
    end
  end
end
