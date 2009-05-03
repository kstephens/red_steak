
module RedSteak

  # Renders a StateMachine as a Dot syntax stream.
  #
  # Can also render SVG to a file or a String, if graphvis is installed.
  #
  # Example output:
  #
  # link:example/red_steak-loan_application-09.dot.svg
  #
  # More examples here:
  #
  # link:example/
  #
  class Dot < Base
    @@verbose = false
    def self.verbose; @@verbose; end
    def self.verbose= x; @@verbose = x; end

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

    attr_accessor :logger
    attr_accessor :log_level

    attr_reader :dot_command_output

    def initialize opts = { }
      @dot_name = { }
      @dot_label = { }
      @rendered = { }
      @dot_command_output = nil
      @dot_id = 0
      @logger = nil
      @log_level = :debug
      super
    end


    def dot_name x, context = nil
      case context
      when Array
        r = dot_name(x)
        context.each { | c | @dot_name[[ x, c ]] = r }
        r
      else
        @dot_name[[ x, context ]] ||= 
          _dot_name(x, context)
      end
    end


    def _dot_name x, context
      @dot_id +=1
      prefix = "x"
      suffix = nil
      case x
      when State
        if ssm = x.submachine
          case context
          when :source, :target
            suffix = "_#{context}"
          end
        end
      when StateMachine
        prefix = "cluster_#{prefix}"
        case context
        when :start
          suffix = "_START"
        end
      end
      prefix << @dot_id.to_s
      prefix << suffix if suffix
      prefix
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
        x.name.to_s

      when State
        label = x.name.to_s

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

      # See UML Spec 2.1 superstructure p. 574:
      #   trigger [ ',' trigger ]* [ '[' guard ']' ]? [ '/' effect ]?
      when Transition
        label = x.trigger.empty? ? "'#{x.name.to_s}'" : x.trigger.join(', ')
        
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
          _log { "WARNING: #{self.class} option[#{k.inspect}] is deprecated, use option[#{v.inspect}]" }
          options[v] = options[k]
        end
      end

      @stateMachine ||= sm
      stream.puts "\n// {#{sm.inspect}"
      # type = :graph
      type = :digraph
      stream.puts "#{type} #{dot_name(sm)} {"

=begin
      stream.puts %Q{  node [fontname="Verdana"]; }
      stream.puts %Q{  fontname="Verdana"; }
=end
      stream.puts %Q{  label=#{dot_label(sm).inspect}; }
 
      # stream.puts "subgraph ROOT {"

      start_name = dot_name(sm, :start)
      @rendered[start_name] = true
      stream.puts "\n// Implicit :start Pseudostate for #{sm.to_s}"
      stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{start_name}; }

      sm.states.each { | s | render_State(s) }
      
      render_transitions(sm)

      stream.puts "}"
      # stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end


    def render_transitions sm
      sm.transitions.each { | t | render(t) }
      sm.states.each do | s |
        start_name = dot_name(s.stateMachine, :start)
        if s.start_state? && @rendered[start_name]
          stream.puts "\n// Implicit Transition to :start Pseudostate for #{sm.to_s}"
          stream.puts "#{start_name} -> #{dot_name(s, :target)};"
        end
        if ssm = s.submachine
          if false
            stream.puts "\n// Implicit source and target grouping link"
            stream.puts %Q{#{dot_name(s, :source)} -> #{dot_name(s, :target)} [ color="gray", label="", arrowhead="none" ];}
          end
          render_transitions(ssm)
        end
      end
    end


    # Renders the StateMachine as Dot syntax.
    def render_StateMachine sm, dot_opts = nil
      return if @rendered[sm]
      @rendered[sm] = true

      dot_opts ||= { }
      hide_decomposition = dot_opts.delete(:hide_decomposition)

      stream.puts "\n// {#{sm.inspect}"
      name = dot_opts.delete(:_node_name) || dot_name(sm)
      type = "subgraph #{name}"

      dot_opts[:label] ||= dot_label(sm.superstate)
      dot_opts[:shape] = :box
      dot_opts[:style] = 'filled,rounded'
      dot_opts[:fillcolor] ||= :white
      dot_opts[:fontcolor] ||= :black

      dot_opts = dot_opts_for sm, dot_opts

      if hide_decomposition && false
        dot_opts[:label] += "\\r    o-o"
      end
 
      stream.puts "#{type} {"
      stream.puts %Q{  #{render_opts(dot_opts, ";\n  ")}}
      
      yield if block_given?

      unless hide_decomposition
        start_name = dot_name(sm, :start)
        @rendered[start_name] = true
        stream.puts "\n// Implicit :start Pseudostate"
        stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{start_name}; }
        sm.states.each { | s | render(s) }
      end

      stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end 
    

    # Renders the State object as Dot syntax.
    def render_State s
      return if @rendered[s]
      @rendered[s] = true

      stream.puts "\n// #{s.inspect}"
      
      sequence = [ ]
      
      if options[:history]
        options[:history].each_with_index do | hist, i |
          if hist[:new_state] && s.is_a_superstate_of?(hist[:new_state])
            sequence << i + 1
          end
        end
      end

      dot_opts = {
        :label => dot_label(s),
        :color => :black,
        :shape => :box,
        :style => "filled",
      }

      case
      when s.end_state?
        dot_opts[:label] = "" # DONT BOTH LABELING END STATES.
        dot_opts[:shape] = :doublecircle
      end

      dot_opts = dot_opts_for s, dot_opts

      hide_decomposition = dot_opts.delete(:hide_decomposition)
      stream.puts "  // hide_decomposition = #{hide_decomposition.inspect}"

      if (hs = options[:highlight_states]) && hs.include?(s)
        dot_opts[:style] += ',bold'
      end

      unless sequence.empty?
        if options[:highlight_state_history] && (s.submachine ? hide_decomposition : true)
          dot_opts[:fillcolor] = :grey
        end
        if options[:show_state_sequence] 
          dot_opts[:label] += "\\n(#{sequence_to_s(sequence)})\\r"
        end
      end

      dot_opts[:fontcolor] ||= :black
      dot_opts[:fillcolor] ||= :white

      # Dont label FinalStates, it causes too much clutter.
      # Invert the colors to be more like UML.
      case
      when s.end_state?
        dot_opts[:label] = "" 
        dot_opts[:fillcolor], dot_opts[:fontcolor] =
          dot_opts[:fontcolor], dot_opts[:fillcolor]
      end

      if ssm = s.submachine
        # Composite States are rendered as
        # a subgraph cluster with a target and source "connection point" for external connections.
        # This is where the dot_name(s, :source || :target) is defined.
        # Subsequence Transitions edges will used these connnection points.
        implicit_dot_opts = dot_opts.dup
        dot_opts[:hide_decomposition] = hide_decomposition
        render_StateMachine(ssm, dot_opts) do
          dot_opts = implicit_dot_opts
          dot_opts[:shape] = :point
          dot_opts[:label] = "[]"

          stream.puts %Q'\n  subgraph cluster_#{dot_name(s, :source)} {'
          stream.puts %Q{    color=none;}
          stream.puts %Q{    fillcolor=none;}
          stream.puts %Q{    fontcolor=none;}
          stream.puts %Q{    label="";}
          stream.puts %Q{    shape="plaintext";}
          stream.puts %Q{    style="none";}

          dot_opts[:color] = :black
          dot_opts[:fillcolor] = :black
          stream.puts "\n// Implicit target point for State #{s.to_s}"
          stream.puts %Q{  node [ #{render_opts(dot_opts)} ] #{dot_name(s, :target)};}

          dot_opts[:color] = :black
          dot_opts[:fillcolor] = :white
          stream.puts "\n// Implicit source point for State #{s.to_s}"
          stream.puts %Q{  node [ #{render_opts(dot_opts)} ] #{dot_name(s, :source)};}
          stream.puts "\n  }\n"
        end
        return self
      end

      # Non-composite States are rendered as simple nodes.
      # In this case dot_name(s, :source || :target) == dot_name(s).
      dot_opts[:style] += ',rounded'
      stream.puts %Q{  node [ #{render_opts(dot_opts)} ] #{dot_name(s, [:source, :target])};}

      return self
    end


    # Renders the Dot syntax for the Transition.
    def render_Transition t
      return if @rendered[t]
      @rendered[t] = true

      # Do not render Transition if source and target States are both rendered.
      return unless @rendered[t.target] && @rendered[t.source]

      sequence = [ ]
      
      if options[:history]
        # $stderr.puts "\n  trans = #{t.inspect}, sm = #{t.stateMachine.inspect}"
        options[:history].each_with_index do | hist, i |
          if hist[:transition] === t
            # $stderr.puts "  #{i} hist = #{hist.inspect}"
            sequence << i
          end
        end
      end

      stream.puts "\n// #{t.inspect}"

      # $stderr.puts "  #{t.inspect}\n    #{options.inspect}"

      dot_opts = { 
        :label => dot_label(t),
      }

      dot_opts = dot_opts_for t, dot_opts

      if (ht = options[:highlight_transitions]) && ht.include?(t)
        dot_opts[:style] = 'bold'
      end

      source_name = "#{dot_name(t.source, :source)}"
      target_name = "#{dot_name(t.target, :target)}"

      unless sequence.empty?
        if options[:show_transition_sequence]
          dot_opts[:label] = "(#{sequence_to_s(sequence)}) #{dot_opts[:label]}"
        end
      else
        if options[:highlight_transition_history]
          dot_opts[:color] = :grey
          dot_opts[:fontcolor] = :grey
        end        
      end

      dot_opts[:color] ||= :black
      dot_opts[:fontcolor] ||= :black

      return if dot_opts[:visible] == false

      stream.puts "#{source_name} -> #{target_name} [ #{render_opts(dot_opts)} ];"

      self
    end


    def sequence_to_s s, limit = 4
      s = s.sort
      s.uniq!
      if s.size <= limit
        t = s
      else
        t = [ ]
        s.each do | i |
          case (r = t[-1]) 
          when nil
          when Range
            if r.last == i - 1
              t[-1] = (r.first .. i)
            else
              r = nil
            end
          else
            if r == i - 1
              t[-1] = (r .. i)
            else
              r = nil
            end
          end
          t << i unless r
        end
      end
      if t.size > limit
        t = t[0 .. 3] << "\01" << t[-1]
      end
      t.join(',').gsub(/\.\./, '-').sub("\01", '...')
    end


    def dot_opts_for x, opts = nil
      opts ||= { }

      kind = 
      case x
      when StateMachine
        :graph
      when State
        :node
      when Transition
        :edge
      else
        nil
      end

      # overlay based on representation type.
      opts.update((options[:dot_options] || EMPTY_HASH)[kind] || EMPTY_HASH)

      # overlay based on class of element.
      opts.update((options[:dot_options] || EMPTY_HASH)[x.class] || EMPTY_HASH)

      # overlay element's options[:dot_options]
      opts.update(x.options[:dot_options] || EMPTY_HASH)

      # overlay based on object.
      opts.update((options[:dot_options] || EMPTY_HASH)[x] || EMPTY_HASH)

      opts
    end


    def render_opts x, j = ', '
      case x
      when Hash
        x = x.keys.sort { | a, b | a.to_s <=> b.to_s }.map do | k |
          v = x[k]
          case k
          # when :label
          #  v = "<#{v.to_s}>" # HTML see http://www.graphviz.org/doc/info/shapes.html#html
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


    # _machine_ can be a Machine or a Statemachine object.
    #
    # Returns self.
    #
    # File Options: 
    #
    #   :dir  
    #     The directory to create the .dot and .dot.svg files.
    #     Defaults to '.'
    #   :name 
    #     The base filename to use.  Defaults to the name of
    #     StateMachine object.
    #
    # History options:
    #
    #   :show_history
    #     If true, the history stored in Machine is shown as
    #     numbered transitions between states.
    #   :history
    #     An enumeration of Hashes as stored in Machine#history.
    #
    # States Options:
    #   :show_state_sequence
    #   :show_entry
    #   :show_exit
    #   :show_do
    #   :highlight_states
    #     An enumeration of States to highlight.
    #
    # Transition Options:
    #   :show_transition_sequence
    #   :show_guard
    #   :show_effect
    #   :highlight_transitions
    #     An enumeration of Transitions to highlight.
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
      else
        raise ArgumentError, "expected Machine or StateMachine, given #{machine.class}"
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

        # Try using cairo svg renderer.
        cmd = "dot -Tsvg:cairo:cairo #{file_dot.inspect} -o #{file_svg.inspect}"
        _log { "Run: #{cmd}" }
        result = @dot_command_output = `#{cmd} 2>&1`

        # Fall back to plain svg renderer.
        if result =~ /Warning: language .* not recognized, use one of:/
          cmd = "dot -Tsvg #{file_dot.inspect} -o #{file_svg.inspect}"
          _log { "Run: #{cmd}" }
          result = @dot_command_output = `#{cmd} 2>&1`
        end

        # Check for file.
        unless File.exist?(file_svg)
          err = Error.new(:message => 'dot command failed', 
                          :command => cmd, 
                          :file => file_svg,
                          :output => @dot_command_output)
          # $stderr.puts "Error: #{err.inspect}"
          _log { "Error: #{err.inspect}" }
          raise err
        end

        _log { "Generated: file://#{file_svg}" }
      else
        _log { "Warning: #{cmd} failed" }
        raise Error, :message => 'dot command not found', 
          :command => cmd
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


    def _log msg = nil
      msg ||= yield
      case 
      when Proc === @logger
        @logger.call(msg)
      when ::IO === @logger || @@verbose
        @logger ||= $stderr
        @logger.puts "#{self.inspect} #{@stateMachine} #{msg}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        @logger.send(log_level || :debug, msg)
      end
    end
  end # class

end # module


###############################################################################
# EOF

