module Babushka
  class DepDefiner
    include ShellHelpers
    include PromptHelpers
    include VersionList

    attr_reader :payload, :source_path

    delegate :name, :to => :dependency
    delegate :set, :merge, :var, :define_var, :to => :runner

    def default_blocks
      self.class.default_blocks
    end
    def self.default_blocks
      merged_default_blocks_for self
    end
    def self.merged_default_blocks_for klass
      parent_values = klass == DepDefiner ? {} : merged_default_blocks_for(klass.superclass)
      parent_values.merge(default_blocks_for(klass))
    end
    def self.default_blocks_for klass
      (@@default_blocks ||= Hashish.hash)[klass]
    end

    def initialize dep, &block
      @dep = dep
      @payload = {}
      @block = block
      @source_path = self.class.current_load_path
    end

    def dependency
      @dep
    end

    def runner
      @dep.runner
    end

    def define_and_process
      process
      instance_eval &@block unless @block.nil?
    end

    def process
      true # overridden in subclassed definers
    end

    def self.current_load_path
      @@current_load_path ||= nil
    end

    def self.accepted_blocks
      default_blocks.keys
    end

    def self.load_deps_from path
      $stdout.flush
      previous_length, previous_skipped = Dep.deps.length, Dep.skipped
      Dir.glob(pathify(path) / '**/*.rb').each {|f|
        @@current_load_path = f
        begin
          require f
          @@current_load_path = nil
        rescue Exception => e
          log_error "#{e.backtrace.first}: #{e.message}"
          log "Check #{(e.backtrace.detect {|l| l[f] } || f).sub(/\:in [^:]+$/, '')}."
          debug e.backtrace * "\n"
          return nil
        end
      }
      log_ok "Loaded #{Dep.deps.length - previous_length}#{" and skipped #{Dep.skipped - previous_skipped}" unless Dep.skipped == previous_skipped} deps from #{path}."
    end

    def self.accepts_block_for method_name, &default_block
      default_blocks_for(self)[method_name] = default_block
      class_eval %Q{
        def #{method_name} *args, &block
          payload[#{method_name.inspect}] ||= {}
          if block.nil?
            block_for #{method_name.inspect}
          else
            store_block_for #{method_name.inspect}, args, block
          end
        end
      }
      set_up_delegating_for method_name
    end

    def default_task task_name
      differentiator = host.differentiator_for payload[task_name].keys
      L{
        send({:met? => :log_extra, :meet => :log_extra}[task_name] || :debug, [
          "#{@dep.name} / #{task_name} not defined",
          "#{" for #{differentiator}" unless differentiator.nil?}",
          {
            :met => ", moving on",
            :meet => " - nothing to do"
          }[task_name],
          "."
        ].join)
        true
      }
    end


    private

    def store_block_for method_name, args, block
      payload[method_name] ||= {}
      opts = {:on => :unassigned}.merge(args.first || {})
      store_block_for method_name, [{:on => :all}], payload[method_name].delete(:unassigned) unless payload[method_name][:unassigned].nil?
      [method_name, payload[method_name][opts[:on]] = block]
    end

    def block_for method_name
      payload[method_name][(host.match_list & payload[method_name].keys).push(:unassigned).first] ||
      default_blocks[method_name] ||
      default_task(method_name)
    end

    def self.set_up_delegating_for method_name
      runner_class.send :delegate, method_name, :to => :definer
    end

    def self.runner_class
      Object.recursive_const_get name.to_s.sub('Definer', 'Runner')
    end

  end
end
