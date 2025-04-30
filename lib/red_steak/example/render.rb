module RedSteak::Example
  class Render
    include RedSteak::Logging

    attr_accessor :context, :machine, :graph_id, :opts

    def initialize opts = { }
      opts = opts.dup
      @context = opts.delete(:context)
      @machine = opts.delete(:machine)
      @graph_id = opts.delete(:graph_id) || 1
      @opts = opts
    end

    def render_graph! opts = { }
      _log context.inspect if context
      graph_id = self.graph_id
      self.graph_id += 1
      base_dir = File.expand_path("../../../doc/example", File.dirname(__FILE__))
      opts = {
        dir: "#{base_dir}/#{machine.statemachine.name}",
        # name_prefix: 'red_steak-',
        name_suffix: "-%02d" % graph_id,
        show_state_sequence: true,
        show_transition_sequence: true,
        highlight_state_history: true,
        highlight_transition_history: true,
        show_effect: true,
        show_guard: true,
        show_entry: true,
        show_exit: true,
        show_do: true,
      }.merge(self.opts).merge(opts)

      FileUtils.mkdir_p(opts[:dir])
      dot = RedSteak::Dot.new
      # dot.logger = lambda { | msg | $stderr.puts msg }
      dot.render_graph(machine, opts)
      $stderr.puts "## Wrote : #{dot.file_svg}"
      dot
    rescue RedSteak::Error => err
      $stderr.puts "#! ERROR : #{err.inspect}\n#{err.backtrace * "\n"}"
      raise err unless err.to_s =~ /dot command failed/ # Old versions of dot might SEGV!
      # pp machine.history
    end
  end
end
