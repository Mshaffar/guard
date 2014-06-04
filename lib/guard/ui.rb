require 'lumberjack'

require 'guard/options'
require 'guard/ui/colors'

module Guard

  # The UI class helps to format messages for the user. Everything that is logged
  # through this class is considered either as an error message or a diagnostic
  # message and is written to standard error ($stderr).
  #
  # If your Guard plugin does some output that is piped into another process for further
  # processing, please just write it to STDOUT with `puts`.
  #
  module UI
    include Colors

    class << self

      # Get the Guard::UI logger instance
      #
      def logger
        @logger ||= begin
          Lumberjack::Logger.new(options.fetch(:device) { $stderr }, options)
        end
      end

      # Get the logger options
      #
      # @return [Hash] the logger options
      #
      def options
        @options ||= ::Guard::Options.new(level: :info, template: ':time - :severity - :message', time_format: '%H:%M:%S')
      end

      # Set the logger options
      #
      # @param [Hash] options the logger options
      # @option options [Symbol] level the log level
      # @option options [String] template the logger template
      # @option options [String] time_format the time format
      #
      def options=(options)
        @options = ::Guard::Options.new(options)
      end

      # Show an info message.
      #
      # @param [String] message the message to show
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def info(message, options = {})
        _filtered_logger_message(message, :info, nil, options)
      end

      # Show a yellow warning message that is prefixed with WARNING.
      #
      # @param [String] message the message to show
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def warning(message, options = {})
        _filtered_logger_message(message, :warn, :yellow, options)
      end

      # Show a red error message that is prefixed with ERROR.
      #
      # @param [String] message the message to show
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def error(message, options = {})
        _filtered_logger_message(message, :error, :red, options)
      end

      # Show a red deprecation message that is prefixed with DEPRECATION.
      # It has a log level of `warn`.
      #
      # @param [String] message the message to show
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def deprecation(message, options = {})
        warning(message, options) if ::Guard.options[:show_deprecations]
      end

      # Show a debug message that is prefixed with DEBUG and a timestamp.
      #
      # @param [String] message the message to show
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def debug(message, options = {})
        _filtered_logger_message(message, :debug, :yellow, options)
      end

      # Reset a line.
      #
      def reset_line
        $stderr.print(color_enabled? ? "\r\e[0m" : "\r\n")
      end

      # Clear the output if clearable.
      #
      def clear(options = {})
        if ::Guard.options[:clear] && (@clearable || options[:force])
          @clearable = false
          system('clear;')
        end
      end

      # Allow the screen to be cleared again.
      #
      def clearable
        @clearable = true
      end

      # Show a scoped action message.
      #
      # @param [String] action the action to show
      # @param [Hash] scope hash with a guard or a group scope
      #
      def action_with_scopes(action, scope)
        first_non_blank_scope = _first_non_blank_scope(scope)
        scope_message = first_non_blank_scope.map(&:title).join(', ') unless first_non_blank_scope.nil?

        info "#{ action } #{ scope_message || 'all' }"
      end

      private

      # Returns the first non-blank scope by searching in the given `scope`
      # hash and in Guard.scope. Returns nil if no non-blank scope is found.
      #
      def _first_non_blank_scope(scope)
        [:plugins, :groups].each do |scope_name|
          s = scope[scope_name] || ::Guard.scope[scope_name]
          return s if !s.nil? && !s.empty?
        end

        nil
      end

      # Filters log messages depending on either the
      # `:only`` or `:except` option.
      #
      # @param [String] plugin the calling plugin name
      # @yield When the message should be logged
      # @yieldparam [String] param the calling plugin name
      #
      def _filter(plugin)
        only   = options[:only]
        except = options[:except]
        plugin = plugin || calling_plugin_name

        if (!only && !except) || (only && only.match(plugin)) || (except && !except.match(plugin))
          yield plugin
        end
      end

      # Display a message of the type `method` and with the color `color_name`
      # (no color by default) conditionnaly given a `plugin_name`.
      #
      # @param [String] plugin_name the calling plugin name
      # @option options [Boolean] reset whether to clean the output before
      # @option options [String] plugin manually define the calling plugin
      #
      def _filtered_logger_message(message, method, color_name, options = {})
        message = color(message, color_name) if color_name

        _filter(options[:plugin]) do |plugin|
          reset_line if options[:reset]
          logger.send(method, message, plugin)
        end
      end

      # Tries to extract the calling Guard plugin name
      # from the call stack.
      #
      # @param [Integer] depth the stack depth
      # @return [String] the Guard plugin name
      #
      def calling_plugin_name(depth = 2)
        name = /(guard\/[a-z_]*)(\/[a-z_]*)?.rb:/i.match(caller[depth])
        name ? name[1].split('/').map { |part| part.split(/[^a-z0-9]/i).map { |word| word.capitalize }.join }.join('::') : 'Guard'
      end

      # Checks if color output can be enabled.
      #
      # @return [Boolean] whether color is enabled or not
      #
      def color_enabled?
        if @color_enabled.nil?
          if RbConfig::CONFIG['target_os'] =~ /mswin|mingw/i
            if ENV['ANSICON']
              @color_enabled = true
            else
              begin
                require 'rubygems' unless ENV['NO_RUBYGEMS']
                require 'Win32/Console/ANSI'
                @color_enabled = true
              rescue LoadError
                @color_enabled = false
                info "You must 'gem install win32console' to use color on Windows"
              end
            end
          else
            @color_enabled = true
          end
        end

        @color_enabled
      end

      # Colorizes a text message. See the constant in the UI class for possible
      # color_options parameters. You can pass optionally :bright, a foreground
      # color and a background color.
      #
      # @example
      #
      #   color('Hello World', :red, :bright)
      #
      # @param [String] text the text to colorize
      # @param [Array] color_options the color options
      #
      def color(text, *color_options)
        color_code = ''
        color_options.each do |color_option|
          color_option = color_option.to_s
          if color_option != ''
            unless color_option =~ /\d+/
              color_option = const_get("ANSI_ESCAPE_#{ color_option.upcase }")
            end
            color_code += ';' + color_option
          end
        end
        color_enabled? ? "\e[0#{ color_code }m#{ text }\e[0m" : text
      end

    end

  end
end
