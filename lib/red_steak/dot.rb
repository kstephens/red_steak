
module RedSteak

  # Renders a StateMachine as a Dot syntax stream.
  class Dot < Base
    # The root statemachine to be rendered.
    attr_accessor :stateMachine
    alias :statemachine  :stateMachine  # not UML
    alias :statemachine= :stateMachine= # not UML

    # The output stream.
    attr_accessor :stream

    # The output Dot file.
    attr_accessor :file_dot

    # The output SVG file.
    attr_accessor :file_svg

    
    def initialize opts = { }
      @dot_name = { }
      @dot_id = 0
      super
    end


    # Returns the Dot name for the object.
    def dot_name x
      case 
      when StateMachine
        x.submachineState ? "#{dot_name(x.submachineState)}#{SEP}#{x.name}" : x.name.to_s
      when State
        "#{dot_name(x.stateMachine)}#{SEP}#{x.name}" # x.inspect
#      when Transition
      else
        raise ArgumentError, x
      end
    end


    def dot_name x
      (@dot_name ||= { })[x] ||= "x#{@dot_id += 1}"
    end


    # Returns the Dot label for the object.
    def dot_label x
      case
      when StateMachine, State, Transition
        x.to_s
      when String, Integer
        x.to_s
      else
        raise ArgumentError, x
      end
    end


    # Renders object as Dot syntax.
    def render x = @stateMachine
      case x
      when Machine
        options[:history] ||= x.history
        render x.stateMachine
      when StateMachine
        render_root x
      when State
        render_State x
      when Transition
        render_Transition x
      else
        raise ArgumentError, x
      end
    end


    def render_root sm
      @stateMachine ||= sm
      stream.puts "\n// {#{sm.inspect}"
      stream.puts "digraph #{dot_name(sm)} {"

=begin
      stream.puts %Q{  node [fontname="Verdana"]; }
      stream.puts %Q{  fontname="Verdana"; }
=end
      stream.puts %Q{  label=#{dot_label(sm).inspect}; }
 
      # stream.puts "subgraph ROOT {"

      stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{(dot_name(sm) + "_START")}; }

      sm.states.each { | s | render_State(s) }
      
      render_transitions(sm)

      stream.puts "}"
      # stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end


    def render_transitions sm
      sm.transitions.each { | t | render(t) }
      sm.states.each do | s |
        if s.start_state?
          stream.puts "#{(dot_name(s.stateMachine) + '_START')} -> #{dot_name(s)};"
        end
        if ssm = s.submachine
          render_transitions(ssm)
        end
      end
    end


    # Renders the StateMachine as Dot syntax.
    def render_StateMachine sm, dot_opts = { }
      stream.puts "\n// {#{sm.inspect}"
      type = "subgraph cluster_#{dot_name(sm)}"

      dot_opts[:label] ||= dot_label(sm.superstate)
      dot_opts[:shape] = :box
      dot_opts[:style] = 'filled,rounded'
      dot_opts[:fillcolor] ||= :white
      dot_opts[:fontcolor] ||= :black

      stream.puts "#{type} {"

      stream.puts %Q{  label=#{dot_opts[:label].inspect}; }
      stream.puts %Q{  shape="#{dot_opts[:shape]}"; }
      stream.puts %Q{  style="#{dot_opts[:style]}"; }
      stream.puts %Q{  fillcolor=#{dot_opts[:fillcolor]}; }
      stream.puts %Q{  fontcolor=#{dot_opts[:fontcolor]}; }

      stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{(dot_name(sm) + "_START")}; }

      sm.states.each { | s | render(s) }

      stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end 
    

    # Renders the State object as Dot syntax.
    def render_State s
      stream.puts "\n// #{s.inspect}"

      dot_opts = {
        :color => :black,
        :label => s.name.to_s,
        :shape => :box,
        :style => :filled,
      }

      case
      when s.end_state?
        dot_opts[:shape] = :doublecircle
        dot_opts[:fillcolor] = :black
        dot_opts[:fontcolor] = :white
      else
        dot_opts[:fillcolor] = :white
        dot_opts[:fontcolor] = :black
      end

      if options[:show_history] && options[:history]
        sequence = [ ]

        options[:history].each_with_index do | hist, i |
          if (s0 = hist[:previous_state] === s) || 
             (s1 = hist[:new_state] === s)
            # $stderr.puts "hist = #{hist.inspect} i = #{i.inspect}"
            case
            when s0
              sequence << i - 1
            when s1
              sequence << i
            end
          end
        end

        sequence.uniq!
        sequence.sort!
        unless sequence.empty?
          if options[:show_history_sequence] 
            dot_opts[:label] += ": (#{sequence * ', '})"
          end
          dot_opts[:fillcolor] = :grey
          dot_opts[:fontcolor] = :black
        end
      end


      if ssm = s.submachine
        render_StateMachine(ssm, dot_opts)
        # stream.puts %Q{#{dot_name(s)} -> #{(dot_name(ssm) + '_START')} [ label="substate", style=dashed ];}
      else
        stream.puts %Q{  node [ shape="#{dot_opts[:shape]}", label=#{dot_opts[:label].inspect}, style="#{dot_opts[:style]},rounded", color=#{dot_opts[:color]}, fillcolor=#{dot_opts[:fillcolor]}, fontcolor=#{dot_opts[:fontcolor]} ] #{dot_name(s)};}
      end
    end


    # Renders the Dot syntax for the Transition.
    def render_Transition t
      stream.puts "\n// #{t.inspect}"

      label = t.name.to_s

      # See UML Spec 2.1 superstructure p. 574
      # Put the Transition#guard in the label.
      if options[:show_guards]
        case x = t.guard
        when nil
          # NOTHING
        when String, Symbol
          label = "#{label} \n[#{x.inspect}]"
        else
          label = "#{label} \n[...]"
        end
      end

      # Put the Transition#effect in the label.
      if options[:show_effects]
        case x = t.effect
        when nil
          # NOTHING
        when String, Symbol
          label = "#{label} \n/#{x.inspect}"
        else
          label = "#{dot_opts[:label]} \n/..."
        end
      end

      dot_opts = { 
        :label => label,
        :color => options[:show_history] ? :gray : :black,
        :fontcolor => options[:show_history] ? :gray : :black,
      }

      source_name = "#{dot_name(t.source)}"
      if ssm = t.source.submachine
        source_name = "#{dot_name(ssm)}_START"
      end

      target_name   = "#{dot_name(t.target)}"
      if ssm = t.target.submachine
        target_name = "#{dot_name(ssm)}_START"
      end


      sequence = [ ]

      if options[:show_history] && options[:history]
        # $stderr.puts "\n  trans = #{t.inspect}, sm = #{t.stateMachine.inspect}"
        options[:history].each_with_index do | hist, i |
          if hist[:transition] === t
            # $stderr.puts "  #{i} hist = #{hist.inspect}"
            sequence << i
          end
        end

        sequence.sort!
        sequence.uniq!
      end

      unless sequence.empty?
        dot_opts[:color] = :black
        dot_opts[:fontcolor] = :black
        sequence.each do | seq |
          stream.puts "#{source_name} -> #{target_name} [ label=#{('(' + seq.to_s + ') ' + t.name.to_s).inspect}, color=#{dot_opts[:color]}, fontcolor=#{dot_opts[:fontcolor]} ];"
        end
      else 
        stream.puts "#{source_name} -> #{target_name} [ label=#{dot_opts[:label].inspect}, color=#{dot_opts[:color]}, fontcolor=#{dot_opts[:fontcolor]} ];"

      end
      
    end


    def render_opts x
      case x
      when Hash
        x.keys.map do | k |
        end.join(', ')
      when Array
      else
        x.to_s.inspect
      end
    end


    # machine can be a Machine or a Statemachine object.
    #
    # Returns self.
    #
    # Options: 
    #   :dir  
    #     The directory to create the .dot and .dot.svg files.
    #     Defaults to '.'
    #   :name 
    #     The base filename to use.  Defaults to the name of
    #     StateMachine object.
    #   :show_history
    #     If true, the history stored in Machine is shown as
    #     numbered transitions between states.
    #
    # Results:
    #
    #   file_dot
    #     The *.dot file.
    #
    #   file_svg
    #     The *.svg file.
    #     Defaults to "#{file_dot}.svg"
    #
    def render_graph(machine, opts={})
      case machine
      when RedSteak::Machine
        sm = machine.statemachine
      when RedSteak::StateMachine
        sm = machine
      end

      # Compute dot file name.
      unless file_dot
        dir = opts[:dir] || '.'
        file = "#{dir}/"
        file += opts[:name_prefix].to_s
        opts[:name] ||= sm.name
        file += opts[:name].to_s 
        file += opts[:name_suffix].to_s
        file += '-history' if opts[:show_history]
        file += ".dot"
        self.file_dot = file
      end

      # Write the dot file.
      File.open(file_dot, 'w') do | fh |
        opts[:stream] = fh
        RedSteak::Dot.new(opts).render(machine)
      end
      opts[:stream] = nil

      # Compute the SVG file name.
      self.file_svg ||= "#{file_dot}.svg"

      # Render dot to SVG.
      cmd = "dot -V"
      if system("#{cmd} >/dev/null 2>&1") == true
        File.unlink(file_svg) rescue nil
        cmd = "dot -Tsvg:cairo:cairo #{file_dot.inspect} -o #{file_svg.inspect}"
        $stderr.puts cmd
        result = `#{cmd} 2>&1`
        if result =~ /Warning: language .* not recognized, use one of:/
          cmd = "dot -Tsvg #{file_dot.inspect} -o #{file_svg.inspect}"
          $stderr.puts cmd
          result = `#{cmd} 2>&1`
        end
        $stdout.puts "View file://#{file_svg}"
      else
        $stderr.puts "Warning: #{cmd} failed"
      end

      self
    end


    # Returns SVG data of the graph, using a temporary file.
    def render_graph_svg_data machine, opts = { }
      require 'tempfile'
      tmp = Tempfile.new("red_steak_dot")
      self.file_dot = tmp.path + ".dot"
      self.file_svg = nil
      render_graph(machine, opts)
      File.open(self.file_svg, "r") { | fh | fh.read }
    ensure
      tmp.unlink rescue nil
      File.unlink(self.file_dot) rescue nil
      File.unlink(self.file_svg) rescue nil
    end

  end # class

end # module


###############################################################################
# EOF

