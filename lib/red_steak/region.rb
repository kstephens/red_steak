
module RedSteak

  # A Region object.
  class Region < Namespace

    # List of State objects.
    # subsets ownedMember
    attr_reader :subvertexs # not UML
    alias :subvertex :subvertexs # UML

  end # class

end # module


###############################################################################
# EOF
