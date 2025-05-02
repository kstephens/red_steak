require 'tempfile'
require 'pry'

module RedSteak
  # Renders a StateMachine as a Dot syntax stream.
  #
  # Can also render SVG to a file or a String, if graphvis is installed.
  #
  # Example output:
  #
  # link:doc/example
  #
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
  # General Options:
  #
  #   :show_all
  #     Same as :show_entry, :show_exit, :show_do, :show_trigger, :show_effect
  #
  # History options:
  #
  #   :show_history
  #     If true, the history stored in Machine is shown as
  #     numbered transitions between states.
  #   :history
  #     An enumeration of Hashes as stored in Machine#history.
  #
  # State Options:
  #
  #   :show_state_sequence
  #   :show_entry
  #   :show_exit
  #   :show_do
  #   :highlight_states
  #     An enumeration of States to highlight.
  #
  # Transition Options:
  #
  #   :show_transition_sequence
  #   :show_guard
  #   :show_effect
  #   :show_trigger
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
  # Color names:
  # * https://graphviz.org/doc/info/colors.html
  #
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

    attr_reader :dot_command_output

    def initialize opts = { }
      @dot_name = { }
      @dot_label = { }
      @rendered = { }
      @dot_command_output = nil
      @dot_id = 1000
      @indent = ""
      @edges = nil
      super
    end

    def render_graph(object, opts = nil)
      opts = self.options.update(opts || {})
      # Map high-level options.
      if options[:show_history]
        %w[show_transition_sequence highlight_state_history highlight_transition_history].each{|k| options[k.to_sym] = true}
      end
      if options[:show_all]
        %w[show_entry show_do show_exit show_effect show_guard show_trigger].each{|k| options[k.to_sym] = true}
      end
      render_dot_file object, opts
      render_svg_file file_dot, file_svg
    end

    def render_dot_file object, opts
      case object
      when RedSteak::Machine
        machine = object
        statemachine = object.statemachine
        name = statemachine
      when RedSteak::StateMachine
        machine = object
        statemachine = object
      else
        raise Error, "expected Machine or StateMachine, given #{machine.class}"
      end

      # Compute dot file name.
      unless file_dot
        dir = opts[:dir] || '.'
        file = "#{dir}/"
        file += opts[:name_prefix].to_s
        opts[:name] ||= name || object.name
        file += opts[:name].to_s
        file += opts[:name_suffix].to_s
        file += '-history' if opts[:show_history]
        file += ".dot"
        self.file_dot = file
      end
      self.file_svg ||= "#{file_dot}.svg"

      # Write the dot file.
      File.open(file_dot, 'w') do | stream |
        @stream = stream
        render object
      end
      @stream = nil
    end

    def render_svg_file file_dot, file_svg
      # Render dot to SVG.
      cmd = "dot -V"
      unless system("#{cmd} >/dev/null 2>&1") == true
        _log { "Warning: #{cmd} failed" }
        raise Error, :message => 'dot command not found',
          :command => cmd
      end

      File.unlink(file_svg) rescue nil

      # Try using cairo svg renderer.
      cmd = "dot -Tsvg:cairo:cairo #{file_dot.inspect} -o #{file_svg.inspect}"
      _log { "Run: #{cmd}" }
      result = @dot_command_output = `#{cmd} 2>&1`
      _log { "Result: #{result}" }

      # Fall back to plain svg renderer.
      if result =~ /Warning: language .* not recognized, use one of:|cairo: out of memory/ || ! File.exist?(file_svg)
        cmd = "dot -Tsvg #{file_dot.inspect} -o #{file_svg.inspect}"
        _log { "Run: #{cmd}" }
        result = @dot_command_output = `#{cmd} 2>&1`
        _log { "Result: #{result}" }
      end

      # Check for file.
      unless File.exist?(file_svg)
        err = Error.new(:message => 'dot command failed',
                        :command => cmd,
                        :file => file_svg,
                        :output => @dot_command_output)
        _log { "Error: #{err.inspect}" }
        raise err
      end

      _log { "Generated: file://#{file_svg}" }

      self
    end

    # Returns SVG data of the graph, using a temporary file.
    def render_graph_svg_data machine, opts = { }
      tmp = Tempfile.new("red_steak_dot")
      self.file_dot = tmp.path + ".dot"
      self.file_svg = nil
      render_graph(machine, opts)
      result = File.read(self.file_svg)
      if opts[:xml_header] == false || options[:xml_header] == false
        result.sub!(/\A.*?<svg /m, '<svg ')
      end
      result
    ensure
      tmp.unlink rescue nil
      File.unlink(self.file_dot) rescue nil
      File.unlink(self.file_svg) rescue nil
    end

    def emit *args
      args.each do |a|
        @stream.write @indent
        @stream.puts a.to_s
      end
      @stream.flush
      # args.each {|a| $stderr.puts a.to_s }
      self
    end

    #################################################################################

    def render x
      case x
      when Machine
        @machine = x
        options[:history] ||= x.history
        options[:highlight_states] ||= [ x.state ].compact
        options[:highlight_transitions] ||= (
          x.transition_queue.map{|e| e.first} <<
          x.transition
        ).compact
        render x.stateMachine
      when StateMachine
        @stateMachine = x
        render_Statemachine x
      when State
        render_State x
      when Transition
        render_Transition x
      else
        raise Error, x.inspect
      end
    end

    def render_Statemachine sm
      # Map high-level options.
      if options[:show_history]
        %w[show_transition_sequence highlight_state_history highlight_transition_history]
        .each {|k| options[k.to_sym] = true}
      end
      if options[:show_all]
        %w[show_entry show_do show_exit show_effect show_guard show_trigger]
        .each {|k| options[k.to_sym] = true}
      end
      dot_opts = {
        label: sm.name,
        shape: :box,
        style: "filled",
        fontcolor: :black,
        color: :white, # :black;
        fillcolor: :white,
      }
      sm_opts = {
        type: :digraph,
        render_start: true,
        render_end: true,
        graph_opts: {
          compound: true,
        },
      }
      @edges = nil
      render_statemachine(sm, dot_opts, sm_opts)
    end

    def render_statemachine sm, dot_opts, sm_opts
      return if rendered?(sm)
      dot_opts = dot_opts.merge(dot_opts_for sm)
      return if dot_opts[:visible] == false

      type = sm_opts.fetch(:type)
      name = dot_name(sm)
      label = sm_opts[:label] || dot_opts[:label] || dot_label(sm)
      dot_opts = dot_opts.merge(sm_opts[:dot_opts] || {}).merge(label: label)
      emit(
        "// #{sm.inspect} ",
        "#{type} #{name} { ",
      )
      _indent, @indent = @indent, @indent + "  "

      if sm_opts[:graph_opts]
        emit("graph [ #{render_opts(sm_opts[:graph_opts])} ];")
      end
      # emit("node  [ #{render_opts(dot_opts)} ];", '')
      emit(*render_opts(dot_opts, ";\n"))

      unless sm_opts[:show_decomposition] == false
        _nodes, @nodes = @nodes, []
        @edges = [] if type == :digraph

        render_states sm, sm_opts
        render_transitions sm, sm_opts

        # @nodes.each{|e| emit(*e)}
        # @nodes = _nodes

        if type == :digraph
          @edges.each{|e| emit(*e)}
          @edges = nil
        end
      end

      @indent = _indent
      emit(
        "}",
        "// } #{sm.inspect}",
        ""
      )
    end

    def render_states sm, sm_opts
      if sm_opts.fetch(:render_start)
        start_name = dot_name(sm, :start)
        desc = "#{sm} <start>"
        render_node(desc, start_name,
          label: "",
          shape: :circle, style: "filled",
          color: :black,
          fillcolor: :black,
          fontcolor: :black,
          # width: 0.5,
        )
      end
      if sm_opts.fetch(:render_end)
        end_name = dot_name(sm, :end)
      end

      sm.states.each do | s |
        if s.start_state? && start_name
          name = dot_name(s)
          render_edge("#{desc} -> ", start_name, name, {})
        end

        opts = render_State s, sm_opts

        if s.end_state? && end_name
          end_opts = opts
          name = dot_name(s)
          render_edge("#{s} -> <end>", name, end_name, {})
        end
      end

      if end_name
        desc = "#{sm} <end>"
        opts = {
          label: "",
          shape: :doublecircle, style: "filled",
          color: :black,
          fillcolor: :black,
          fontcolor: :white,
          # width: 0.5,
        }
        if sm.superstate
          # https://graphviz.org/docs/attrs/style/
          opts.update(style: :invis)
          # opts.update(color: :none, fillcolor: :none, fontcolor: :none)
        end
        render_node(desc, end_name, opts)
      end
    end

    def render_State s, sm_opts
      return if rendered?(s)
      dot_opts = dot_opts_State(s)
      dot_opts = dot_opts.update(dot_opts_for s)
      return if dot_opts[:visible] == false

      show_decomposition = dot_opts.delete(:show_decomposition)
      name = dot_name(s) # , [:source, :target])
      if (sm = s.submachine) && show_decomposition
        sm_opts = {
          type: :subgraph,
          render_start: true,
          render_end: true,
          label: dot_opts[:label],
          show_decomposition: show_decomposition,
          dot_opts: {
            style: "rounded",
          },
        }
        render_statemachine sm, dot_opts, sm_opts
      else
        render_node(s.inspect, name, dot_opts)
      end
      dot_opts
    end

    def render_transitions sm, sm_opts
      sm.transitions.each do | t |
        render_Transition t, sm_opts
      end
    end

    def render_Transition t, sm_opts
      return if rendered?(t)

      unless was_rendered?(t.source) && was_rendered?(t.target)
        emit "// #{t.inspect} : skipped: source or target not rendered"
        return
      end

      dot_opts = {
        label:     dot_label(t),
        color:     :black,
        fontcolor: :black,
      }.update(dot_opts_for t)
      return if dot_opts[:visible] == false

      if (ht = options[:highlight_transitions]) && ht.include?(t)
        dot_opts.update(highlight_transition_reached_options)
      end

      sequence = [ ]
      if options[:history]
        options[:history].each_with_index do | hist, i |
          if hist[:transition] === t
            sequence << i
          end
        end
      end

      label_more = dot_opts[:label] + "#{sequence_to_s(sequence)}\\l"
      if options[:show_transition_sequence]
        dot_opts[:label] = label_more
      else
        # dot_opts[:tooltip] = label_more
      end
      unless sequence.empty?
        if options[:highlight_transition_history]
          dot_opts.update(highlight_transition_reached_options)
        end
      else
        if options[:highlight_transition_history]
          dot_opts.update(highlight_transition_unreached_options)
        end
      end

      if m = t.source.submachine
        source_name = dot_name(m, :end)
        dot_opts[:ltail] = dot_name(m)
      else
        source_name = dot_name(t.source) # , :source)
      end
      if m = t.target.submachine
        target_name = dot_name(m, :start)
        dot_opts[:lhead] = dot_name(m)
      else
        target_name = dot_name(t.target) # , :target)
      end
      render_edge(t, source_name, target_name, dot_opts)

      self
    end

    def render_node desc, name, dot_opts
      emit(
        "// #{desc}",
        "node [ #{render_opts(dot_opts)} ] #{name};",
        "",
      )
    end

    def render_edge desc, source_name, target_name, dot_opts
      @edges << [
        "// #{desc}",
        "#{source_name} -> #{target_name} [ #{render_opts(dot_opts)} ];",
        "",
      ]
    end

    #################################################################################

    def dot_opts_State s
      dot_opts = {
        label:     dot_label(s),
        shape:     :box,
        style:     "filled,rounded",
        fontcolor: :black,
        color:     :black,
        fillcolor: :white,
      }.update(dot_opts_for s)
      if (hs = options[:highlight_states]) && hs.include?(s)
        dot_opts[:style] += ",#{dot_opts[:highlite_state_style] || :bold}"
      end

      sequence = [ ]
      if options[:history]
        options[:history].each_with_index do | hist, i |
          if hist[:new_state] && s.is_a_superstate_of?(hist[:new_state])
            sequence << i + 1
          end
        end
      end

      label_more = dot_opts[:label] + "#{sequence_to_s(sequence)}\\l" # "\\r"
      if options[:show_state_sequence]
        dot_opts[:label] = label_more
      else
        # dot_opts[:tooltip] = label_more
      end
      unless sequence.empty?
        if options[:highlight_state_history]
          dot_opts.update(highlight_state_reached_options)
        end
      else
        if options[:highlight_state_history]
          dot_opts.update(highlight_state_unreached_options)
        end
      end
      if s.superstate && options[:show_superstate_glyph]
        dot_opts[:label] += "\\no-o\\r"
      end
      dot_opts
    end

    #################################################################################

    def dot_name x, context = nil
      case context
      when Array
        r = dot_name(x)
        context.each { | c | @dot_name[[ x, c ]] = r }
        r
      else
        @dot_name[[ x, context ]] ||= _dot_name(x, context)
      end
    end

    def _dot_name x, context = nil
      case x
      when StateMachine
        if context
          return "x#{@dot_id += 1}_#{context}"
        else
          return "cluster_x#{@dot_id += 1}"
        end
      end
      "x#{@dot_id +=1}"
    end

    #################################################################################

    # Returns the Dot label for the object.
    # !!! refactor this to only return annotations
    def dot_label x
      if label = _dot_label(x)
        label.to_s
      else
        return label if label = @dot_label[x.object_id]
        @dot_label[x.object_id] = _dot_label(x)
      end
    end

    def _dot_label x
      case x
      when StateMachine
        x.name.to_s
      when State
        _dot_label_State x
      when Transition
        _dot_label_Transition x
      end
    end

    def _dot_label_State x
      dot_opts = options.merge(dot_opts_for(x))
      label = x.name.to_s

      render_label(x, "#{label}\n", dot_opts,
        [
          [ :show_entry, :entry,      'entry / %s\\l' ],
          [ :show_exit,  :exit,       'exit / %s\\l'  ],
          [ :show_do,    :doActivity, 'do / %s\\l'    ],
        ]
      )
    end

    # See UML Spec 2.1 superstructure p. 574:
    #   trigger [ ',' trigger ]* [ '[' guard ']' ]? [ '/' effect ]?
    def _dot_label_Transition x
        dot_opts = options.merge(dot_opts_for(x))
        dot_opts[:show_name] = true if x.trigger.empty?
        dot_opts[:show_trigger] = true unless dot_opts[:show_name]
        render_label(x, '', dot_opts,
          [
            [ :show_name,    :name,    '%s\n'    ],
            [ :show_trigger, :trigger, '%s\\l'   ],
            [ :show_guard,   :guard,   '[%s]\\l' ],
            [ :show_effect,  :effect,  '/%s\\l'  ],
          ]
        )
    end

    def render_label x, label, dot_opts, patterns
      patterns.each do | (opt, sel, fmt) |
        next unless opt == true || dot_opts[opt]
        case v = x.send(sel)
        when nil
          # NOTHING
        when Array
          v = v.map(&:to_s) * ','
        when String, Symbol
          v = v.inspect
        else
          v = '...'
        end
        if fmt && ! v.nil?
          label += (fmt % v.to_s)
        end
      end
      label
    end

    #################################################################################

    # !!!: parameterize these:
    def highlight_state_reached_options
      {
        fillcolor: :grey85,
        penwidth:  1.75,
        # style:    'rounded,bold,filled',
      }
    end
    def highlight_state_unreached_options
      {
        fontcolor: :grey33,
        penwidth:  1.0,
        # style:   'rounded,dashed,filled',
      }
    end
    def highlight_transition_reached_options
      {
        # style:    'bold',
        penwidth:  1.75,
      }
    end
    def highlight_transition_unreached_options
      {
        # color:     :grey55,
        # fontcolor: :grey45,
        penwidth:  1.0,
        style: :dashed,
      }
    end

    def sequence_to_s s, limit = 4
      s = s.sort
      s.uniq!
      return '' if s.size.zero?
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
      '(' + t.join(',').gsub(/\.\./, '-').sub("\01", '...') + ')'
    end

    def rendered? obj
      if @rendered[obj.object_id]
        true
      else
        @rendered[obj.object_id] = obj
        false
      end
    end
    def was_rendered? obj
      @rendered[obj.object_id]
    end

    def dot_opts_for x
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

      opts = {}

      # binding.pry
      # overlay based on representation type.
      opts.update((options[:dot_options] || EMPTY_HASH)[kind] || EMPTY_HASH)
      # binding.pry if opts[:label] =~ /::/

      # overlay based on class of element.
      opts.update((options[:dot_options] || EMPTY_HASH)[x.class] || EMPTY_HASH)
      # binding.pry if opts[:label] =~ /::/

      # overlay element's options[:dot_options]
      opts.update(x.options[:dot_options] || EMPTY_HASH)
      # binding.pry if opts[:label] =~ /::/

      # overlay based on object.
      opts.update((options[:dot_options] || EMPTY_HASH)[x] || EMPTY_HASH)
      # binding.pry if opts[:label] =~ /::/

      opts
    end

    def render_opts x, sep = ', '
      items =
      case x
      when Hash
        x.keys.map do | k |
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
      when Array
        x
      else
        [x.to_s.inspect]
      end
      if sep[0] == ";"
        indent = ''
        items.map do |s|
          "#{indent}#{s}#{sep}".tap{indent = @indent}
        end.join('')
      else
        items * sep
      end
    end
  end
end
