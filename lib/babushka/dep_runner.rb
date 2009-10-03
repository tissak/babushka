module Babushka
  module DepRunnerHelpers
    def self.included base # :nodoc:
      base.send :include, HelperMethods
    end

    module HelperMethods
    end
  end

  class DepRunner
    include ShellHelpers
    include PromptHelpers
    include DefinerHelpers

    delegate :source_path, :to => :definer

    def initialize dep
      @dep = dep
    end

    def the_dep
      @dep
    end
    def name
      @dep.name
    end
    def definer
      @dep.definer
    end
    def vars
      Base.task.vars
    end
    def saved_vars
      Base.task.saved_vars
    end

    def set key, value
      vars[key.to_s][:value] = value
    end
    def set_if_unset key, value
      vars[key.to_s][:value] ||= value
    end
    def merge key, value
      set key, ((vars[key.to_s] || {})[:value] || {}).merge(value)
    end

    def var name, opts = {}
      define_var name, opts
      if vars[name.to_s].has_key? :value
        vars[name.to_s][:value]
      elsif opts[:ask] != false
        ask_for_var name.to_s
      end
    end

    def define_var name, opts = {}
      vars[name.to_s].update opts.dragnet(:default, :type, :message)
    end

    def ask_for_var key
      set key, send("prompt_for_#{vars[key][:type] || 'value'}",
        message_for(key),
        :default => default_for(key), :dynamic => vars[key][:default].respond_to?(:call)
      )
    end

    def message_for key
      printable_key = key.to_s.gsub '_', ' '
      vars[key][:message] || "#{printable_key}#{" for #{name}" unless printable_key == name}"
    end

    def default_for key
      if vars[key.to_s][:default].respond_to? :call
        # If the default is a proc, re-evaluate it every time.
        instance_eval { vars[key.to_s][:default].call }
      # Symbol defaults are references to other vars.
      elsif vars[key.to_s][:default].is_a? Symbol
        # Look up the current value of the referenced var.
        referenced_val = var vars[key.to_s][:default], :ask => false
        # Use the corresponding saved value if there is one, otherwise use the reference.
        (saved_vars[key.to_s][:values] ||= {})[referenced_val] || referenced_val
      else
        # Otherwise, use a saved literal value, or the default.
        saved_vars[key.to_s][:value] || vars[key.to_s][:default]
      end
    end

  end
end
