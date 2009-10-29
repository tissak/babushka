module Babushka
  module DepHelpers
    def self.included base # :nodoc:
      base.send :include, HelperMethods
    end

    module HelperMethods
      def Dep name;                    Dep.for name.to_s                                        end
      def dep name, opts = {}, &block; Dep.add name, opts, block, BaseDepDefiner, BaseDepRunner end
      def pkg name, opts = {}, &block; Dep.add name, opts, block, PkgDepDefiner , PkgDepRunner  end
      def gem name, opts = {}, &block; Dep.add name, opts, block, GemDepDefiner , GemDepRunner  end
      def src name, opts = {}, &block; Dep.add name, opts, block, SrcDepDefiner , SrcDepRunner  end
      def ext name, opts = {}, &block; Dep.add name, opts, block, ExtDepDefiner , ExtDepRunner  end
    end
  end

  class Dep
    attr_reader :name, :opts, :vars, :definer, :runner
    attr_accessor :unmet_message

    delegate :set, :merge, :define_var, :to => :runner

    def initialize name, in_opts, block, definer_class, runner_class
      @name = name.to_s
      @opts = {
        :for => :all
      }.merge in_opts
      @vars = {}
      @runner = runner_class.new self
      @definer = definer_class.new self, &block
      @definer.define_and_process
      debug "\"#{name}\" depends on #{payload[:requires].inspect}"
      Dep.register self
    end

    def self.add name, in_opts, block, definer_class, runner_class
      if self.for name
        @@skipped += 1
        self.for name
      else
        new name, in_opts, block, definer_class, runner_class
      end
    end

    def self.deps
      @@deps ||= {}
    end
    def self.count
      deps.length
    end
    @@skipped = 0
    def self.skipped
      @@skipped
    end
    def self.names
      @@deps.keys
    end
    def self.all
      @@deps.values
    end
    def self.clear!
      @@deps = {}
    end
    def self.uncache
      all.each {|dep| dep.send :uncache }
    end

    def self.register dep
      raise "There is already a registered dep called '#{dep.name}'." unless deps[dep.name].nil?
      deps[dep.name] = dep
    end
    def self.for name
      deps[name]
    end
    def self.process dep_name
      if (dep = Dep(dep_name)).nil?
        log "#{dep_name.to_s.colorize 'grey'} #{"<- this dep isn't defined!".colorize('red')}"
      else
        dep.process
      end
    end

    def met?
      process :dry_run => true, :top_level => true
    end
    def meet
      process :dry_run => false, :top_level => true
    end

    def process with_run_opts = {}
      task.run_opts.update with_run_opts
      returning cached? ? cached_result : process_and_cache do
        Dep.uncache if with_run_opts[:top_level]
      end
    end

    private

    def process_and_cache
      log name, :closing_status => (task.dry_run? ? :dry_run : true) do
        if task.callstack.include? self
          log_error "Oh crap, endless loop! (#{task.callstack.push(self).drop_while {|dep| dep != self }.map(&:name).join(' -> ')})"
        elsif !host.matches?(opts[:for])
          log_ok "Not required on #{host.differentiator_for opts[:for]}."
        else
          task.callstack.push self
          returning process_in_dir do
            task.callstack.pop
          end
        end
      end
    end

    def process_in_dir
      path = payload[:run_in].is_a?(Symbol) ? vars[payload[:run_in]] : payload[:run_in]
      in_dir path do
        process_task(:internal_setup) and process_task(:setup) and process_deps and process_self
      end
    end

    def process_deps
      @definer.requires.send(task.dry_run? ? :each : :all?, &L{|dep_name|
        Dep.process dep_name
      })
    end

    def process_self
      process_met_task(:initial => true) {
        if task.dry_run?
          false # unmet
        else
          process_task(:before) and process_task(:meet) and process_task(:after)
          process_met_task
        end
      }
    end

    def process_met_task task_opts = {}, &block
      if !(met_result = run_met_task(task_opts))
        if block.nil?
          false # unmet
        else
          block.call
        end
      elsif :fail == met_result
        false # can't be met
      else
        true # already met
      end
    end

    def run_met_task task_opts = {}
      returning cache_process(call_task(:met?)) do |result|
        if :fail == result
          log_extra "I don't know how to fix that, so it's up to you. :)"
        elsif !result && task_opts[:initial]
          log_extra "#{name} not already met#{unmet_message_for(result)}."
        elsif result && !task_opts[:initial]
          log "#{name} met.".colorize('green')
        end
      end
    end

    def process_task task_name
      !call_task(task_name).in? [nil, false, :fail]
    end

    def call_task task_name
      # log "calling #{name} / #{task_name}"
      runner.instance_eval &@definer.send(task_name)
    rescue StandardError => e
      log "#{e.class} during '#{name}' / #{task_name}{}.".colorize('red')
      log "#{e.backtrace.first}: #{e.message}".colorize('red')
      dep_callpoint = e.backtrace.detect {|l| l[definer.source_path] } unless definer.source_path.nil?
      log "Check #{dep_callpoint}." unless dep_callpoint.nil?
      debug e.backtrace * "\n"
      Base.task.reportable = true
      :fail
    end

    def unmet_message_for result
      unmet_message.nil? || result ? '' : " - #{unmet_message}"
    end

    def cached_result
      returning cached_process do |result|
        log_result "#{name} (cached)", :result => result, :as_bypass => task.dry_run?
      end
    end
    def cached?
      !@_cached_process.nil?
    end
    def uncache
      @_cached_process = nil
    end
    def cached_process
      @_cached_process
    end
    def cache_process value
      @_cached_process = (value.nil? ? false : value)
    end

    def payload
      @definer.payload
    end

    def require_counts
      (payload[:requires] || {}).map {|k,v| "#{k.inspect} => #{v.length}" }.join(', ')
    end

    def task
      Base.task
    end

    public

    def inspect
      "#<Dep:#{object_id} '#{name}'#{" #{'un' if cached_process}met" if cached?}, deps = { #{require_counts} }>"
    end
  end
end
