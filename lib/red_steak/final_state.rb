
module RedSteak

  # 
  class FinalState < State

    def validate errors
      e = [ ]
      e << :final_state_has_outgoing_transitions unless outgoing.size == 0
      e << :final_state_has_regions unless region.size == 0
      e << :final_state_references_a_submachine unless submachine == nil
      e << :final_state_has_exit_behavior unless exit == nil
      e << :final_state_has_doActivity_behavior unless doActivity == nil
      e.each do | m |
        errors << [ m, self ]
      end
      errors.push(*e)
    end

  end # class

end # module


###############################################################################
# EOF

