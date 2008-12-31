
module RedSteak

  # 
  class Pseudostate < Vertex
    # See PseudostateKind.
    # initial
    # deepHistory
    # shallowHistory
    # join
    # fork
    # junction
    # choice
    # entryPoint
    # exitPoint
    # teminate
    attr_accessor :kind

    # The state associated with this Pseudostate.
    attr_reader   :state

    def initialize opts = { }
      @kind = :initial
      @state = nil
      super
    end

    def _validate e
      case @kind
      when :initial
        e << :initial_vertex_can_have_at_most_one_outgoing_transition unless outgoing.size <= 1
        e << :outgoing_transition_from_initial_vertex_may_not_have_guard unless outgoing.select{|x| x.guard}.size == 0
      end
    end

  end # class

end # module


###############################################################################
# EOF

