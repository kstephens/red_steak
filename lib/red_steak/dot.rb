
module RedSteak

  # Renders a StateMachine as a Dot syntax stream.
  # Can also render SVG to a file or a String, if graphvis is installed.
  class Dot < Base
    # The root StateMachine to be rendered.
    attr_accessor :stateMachine
    alias :statemachine  :stateMachine  # not UML
    alias :statemachine= :stateMachine= # not UML

    # The root Machine to be rendered.
    attr_accessor :machine

    # The output stream.
    attr_accessor :stream

    # The output Dot file.
    attr_accessor :file_dot

    # The output SVG file.
    attr_accessor :file_svg

    
    def initialize opts = { }
      @dot_name = { }
      @dot_label = { }
      @dot_id = 0
      super
    end


    def dot_name x
      @dot_name[x] ||= 
        "x#{@dot_id += 1}"
    end


    # Returns the Dot label for the object.
    def dot_label x
      @dot_label[x] ||=
        _dot_label x
    end


    def _dot_label x
      # $stderr.puts "  _dot_label #{x.inspect}"
      case x
      when StateMachine
        x.to_s

      when State
        label = x.to_s

        # Put the State#entry,#exit and #doActivity in the label.
        once = false
        [ 
         [ :show_entry, :entry,      'entry / %s' ],
         [ :show_exit,  :exit,       'exit / %s' ],
         [ :show_do,    :doActivity, 'do / %s' ],
        ].each do | (opt, sel, fmt) |
          if options[opt]
            case b = x.send(sel)
            when nil
              # NOTHING
            when String, Symbol
              b = b.inspect
            else
              b = '...'
            end
            if b
              unless once
                label += " \n"
              else
                label += " \\l"
              end
              label += (fmt % b)
              once = true
            end
          end
        end
        
        label

      when Transition
        label = x.name.to_s
        
        # See UML Spec 2.1 superstructure p. 574
        # Put the Transition#guard and #effect in the label.
        [ 
         [ :show_guard,  :guard,  '[%s]' ],
         [ :show_effect, :effect, '/%s' ],
        ].each do | (opt, sel, fmt) |
          if options[opt]
            case b = x.send(sel)
            when nil
              # NOTHING
            when String, Symbol
              b = b.inspect
            else
              b = '...'
            end
            if b
              label += " \n" + (fmt % b)
            end
          end
        end
        
        # $stderr.puts "  _dot_label #{x.inspect} => #{label.inspect}"
        
        label

      when String, Integer
        x.to_s

      else
        raise ArgumentError, x.inspect
      end
    end


    # Renders object as Dot syntax.
    def render x = @stateMachine
      case x
      when Machine
        @machine = x
        options[:history] ||= 
          x.history
        options[:highlight_states] ||= 
          [ x.state ].compact
        options[:highlight_transitions] ||= 
          (
           x.transition_queue.map{|e| e.first} << 
           x.executing_transition
           ).compact
        render x.stateMachine
      when StateMachine
        render_root x
      when State
        render_State x
      when Transition
        render_Transition x
      else
        raise ArgumentError, x.inspect
      end
    end


    def render_root sm
      # Map high-level options.
      if options[:show_history]
        options[:show_transition_sequence] = true
        options[:highlight_state_history] = true
        options[:highlight_transition_history] = true
      end

      # Map deprecated options.
      { 
        :show_guards => :show_guard,
        :show_effects => :show_effect,
      }.each do | k, v |
        if options.key?(k)
          $stderr.puts "WARNING: #{self.class} option[#{k.inspect}] is deprecated, use option[#{v.inspect}]"
          options[v] = options[k]
        end
      end

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

      stream.puts %Q{  #{render_opts(dot_opts, ";\n  ")}}

      stream.puts %Q{node [ shape="circle", label="", style=filled, fillcolor=black ] #{(dot_name(sm) + "_START")}; }

      sm.states.each { | s | render(s) }

      stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end 
    

    # Renders the State object as Dot syntax.
    def render_State s
      stream.puts "\n// #{s.inspect}"
      
      dot_opts = {
        :label => dot_label(s),
        :color => :black,
        :shape => :box,
        :style => "filled",
      }
      
      if (hs = options[:highlight_states]) && hs.include?(s)
        dot_opts[:style] += ',bold'
      end

      case
      when s.end_state?
        dot_opts[:label] = "" # DONT BOTH LABELING END STATES.
        dot_opts[:shape] = :doublecircle
        dot_opts[:fillcolor] = :black
        dot_opts[:fontcolor] = :white
      else
        dot_opts[:fillcolor] = :white
        dot_opts[:fontcolor] = :black
      end

      sequence = [ ]
      
      if options[:history]
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
      end

      unless sequence.empty?
        sequence.uniq!
        sequence.sort!
        if options[:show_state_sequence] 
          dot_opts[:label] += "\\r(#{sequence * ', '})"
        end
        if options[:highlight_state_history]
          dot_opts[:fillcolor] = :grey
          dot_opts[:fontcolor] = :black
        end
      end

      if ssm = s.submachine
        render_StateMachine(ssm, dot_opts)
        # stream.puts %Q{#{dot_name(s)} -> #{(dot_name(ssm) + '_START')} [ label="substate", style=dashed ];}
      else
        dot_opts[:style] += ',rounded'
        stream.puts %Q{  node [ #{render_opts(dot_opts)} ] #{dot_name(s)};}
      end
    end


    # Renders the Dot syntax for the Transition.
    def render_Transition t
      stream.puts "\n// #{t.inspect}"

      # $stderr.puts "  #{t.inspect}\n    #{options.inspect}"

      dot_opts = { 
        :label => dot_label(t),
        :color => options[:highlight_transition_history] ? :gray : :black,
        :fontcolor => options[:highlight_transition_history] ? :gray : :black,
      }

      if (ht = options[:highlight_transitions]) && ht.include?(t)
        dot_opts[:style] = 'bold'
      end

      source_name = "#{dot_name(t.source)}"
      if ssm = t.source.submachine
        source_name = "#{dot_name(ssm)}_START"
      end

      target_name = "#{dot_name(t.target)}"
      if ssm = t.target.submachine
        target_name = "#{dot_name(ssm)}_START"
      end

      sequence = [ ]
      
      if options[:history]
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
        if options[:highlight_transition_history]
          dot_opts[:color] = :black
          dot_opts[:fontcolor] = :black
        end
        if options[:show_transition_sequence]
          dot_opts[:label] = "(#{sequence * ','}) #{dot_opts[:label]}"
        end
      end

      stream.puts "#{source_name} -> #{target_name} [ #{render_opts(dot_opts)} ];"

      self
    end


    def render_opts x, j = ', '
      case x
      when Hash
        x = x.map do | k, v |
          case k
          when :label, :shape, :style
            v = v.to_s.inspect
            # http://www.graphviz.org/doc/info/attrs.html#k:escString
            v.gsub!(/\\\\([lrn])/){ "\\" +$1 }
          end
          "#{k}=#{v}"
        end
        if j =~ /\n/
          x << ''
        end
        x * j
      when Array
        x * ','
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
      result = File.open(self.file_svg, "r") { | fh | fh.read }
      if opts[:xml_header] == false || options[:xml_header] == false
        result.sub!(/\A.*?<svg /m, '<svg ')
      end
      # puts "#{result[0..200]}..."
      result
    ensure
      tmp.unlink rescue nil
      File.unlink(self.file_dot) rescue nil
      File.unlink(self.file_svg) rescue nil
    end

  end # class

end # module


###############################################################################
# EOF

