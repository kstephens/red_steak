module RedSteak
  module Logging
    # The logging object.
    # Can be a Log4r::Logger, Proc or IO object.
    attr_accessor :logger

    # Log level method Symbol if Log4r::Logger === logger.
    # Defaults to :debug.
    attr_accessor :log_level
    def log_level ; @log_level || :debug          ; end

    # A string to embed in the log:
    attr_accessor :log_topic
    def log_topic ; @log_topic || self.class.name ; end

    # A symbol that sets the logging level for Log4r
    attr_accessor :log_verbose

    def _log msg = nil, &blk
      return @log_delegate._log(msg, &blk) if @log_delegate
      logger = self.logger
      if defined?(::Log4r) && (Log4r::Logger === logger)
        logger.send(log_level || :debug, msg, &blk)
      else
        msg ||= yield
        msg = "#{log_topic} #{msg}"
        case
        when Proc === logger
          logger.call(msg)
        when ::IO === logger || log_verbose
          (logger || $stderr).puts "#{self.inspect} #{msg}"
        end
      end
      nil
    end
  end
end
