def shell cmd, opts = {}, &block
  shell_method = opts.delete(:sudo) ? :sudo : :shell_cmd
  send shell_method, cmd, opts, &block
end

def failable_shell cmd, opts = {}
  shell = nil
  Babushka::Shell.new(cmd).run opts.merge(:fail_ok => true) do |s|
    shell = s
  end
  shell
end

def which cmd_name, &block
  result = shell "which #{cmd_name}", &block
  result unless result.nil? || result["no #{cmd_name} in"]
end

require 'fileutils'
def in_dir dir, opts = {}, &block
  if dir.nil?
    yield Dir.pwd
  else
    path = pathify dir
    FileUtils.mkdir_p(path) if opts[:create] unless File.exists?(path)
    if Dir.pwd == path
      yield path
    else
      Dir.chdir path do
        debug "in dir #{dir} (#{path})" do
          yield path
        end
      end
    end
  end
end

def in_build_dir path = '', &block
  in_dir '~/.babushka/src' / path, :create => true, &block
end

def cmd_dir cmd_name
  which("#{cmd_name}") {|shell|
    File.dirname shell.stdout if shell.ok?
  }
end

def sudo cmd, opts = {}, &block
  sudo_cmd = if opts[:su] || cmd[' |'] || cmd[' >']
    "sudo su - #{opts[:as] || 'root'} -c \"#{cmd.gsub('"', '\"')}\""
  else
    "sudo -u #{opts[:as] || 'root'} #{cmd}"
  end
  shell sudo_cmd, opts, &block
end

def log_block message, opts = {}, &block
  log "#{message}...", :newline => false
  returning block.call do |result|
    log result ? ' done.' : ' failed', :as => (result ? nil : :error), :indentation => false
  end
end

def log_shell message, cmd, opts = {}, &block
  log_block message do
    opts.delete(:sudo) ? sudo(cmd, opts, &block) : shell(cmd, opts, &block)
  end
end

def log_shell_with_a_block_to_scan_stdout_for_apps_that_have_broken_return_values message, cmd, opts = {}, &block
  log_block message do
    send opts.delete(:sudo) ? :sudo : :shell, cmd, opts.merge(:failable => true), &block
  end
end

def rake cmd, &block
  sudo "rake #{cmd} RAILS_ENV=#{var :rails_env}", :as => var(:username), &block
end

def rails_rake cmd, &block
  in_dir var(:rails_root) do
    rake cmd, &block
  end
end

def check_file file_name, method_name
  returning File.send method_name, file_name do |result|
    log_error "#{file_name} failed #{method_name.to_s.sub(/[?!]$/, '')} check." unless result
  end
end

def grep pattern, file
  if File.exists?(path = pathify(file))
    output = if pattern.is_a? String
      IO.readlines(path).select {|l| l[pattern] }
    elsif pattern.is_a? Regexp
      IO.readlines(path).grep(pattern)
    end
    output unless output.empty?
  end
end

def change_line line, replacement, filename
  path = pathify filename

  log "Patching #{path}"
  sudo "cat > #{path}", :as => File.owner(path), :input => IO.readlines(path).map {|l|
    l.gsub /^(\s*)(#{Regexp.escape(line)})/, "\\1# #{edited_by_babushka}\n\\1# was: \\2\n\\1#{replacement}"
  }
end

def insert_into_file insert_after, insert_before, filename, lines
  end_of_insertion = "# }\n"
  path = pathify filename
  nlines = lines.split("\n").length
  before, after = IO.readlines(path).cut {|l| l.strip == insert_before.strip }

  log "Patching #{path}"
  if before.last == end_of_insertion
    log_extra "Already written to line #{before.length + 1 - 2 - nlines} of #{filename}."
  elsif before.last.strip != insert_after.strip
    log_error "Couldn't find the spot to write to in #{filename}."
  else
    sudo "cat > #{path}", :as => File.owner(path), :input => [
      before,
      added_by_babushka(nlines).start_with('# { ').end_with("\n"),
      lines.end_with("\n"),
      end_of_insertion,
      after
    ].join
  end
end

def change_with_sed keyword, from, to, file
  if check_file file, :writable?
    # Remove the incorrect setting if it's there
    shell("#{sed} -ri 's/^#{keyword}\s+#{from}//' #{file}")
    # Add the correct setting unless it's already there
    grep(/^#{keyword}\s+#{to}/, file) or shell("echo '#{keyword} #{to}' >> #{file}")
  end
end

def sed
  linux? ? 'sed' : 'gsed'
end

def append_to_file text, file, opts = {}
  if failable_shell("grep '^#{text}' #{file}").stdout.empty?
    shell %Q{echo "# #{added_by_babushka(text.split("\n").length)}\n#{text.gsub('"', '\"')}" >> #{file}}, opts
  end
end

def get_source url, filename = nil
  filename ||= File.basename url.to_s
  archive_dir = archive_basename filename
  if filename.blank?
    log_error "Not a valid URL to download: #{url}"
  elsif archive_dir.blank?
    log_error "Unsupported archive: #{filename}"
  elsif !download(url, filename)
    log_error "Failed to download #{url}."
  elsif !log_shell("Extracting #{filename}", "rm -rf #{archive_dir} && tar -zxf #{filename}")
    log_error "Couldn't extract #{pathify filename}."
    log "(maybe the download was cancelled before it finished?)"
  else
    archive_dir
  end
end

def download url, filename = File.basename(url.to_s)
  if File.exists? filename
    log_ok "Already downloaded #{filename}."
  else
    log_shell "Downloading #{filename}", %Q{curl -L -o "#{filename}" "#{url}"}
  end
end

def archive_basename filename
  File.basename filename, %w[.tar.gz .tgz].detect {|ext| filename.ends_with? ext } || ''
end

def _by_babushka
  "by babushka-#{Babushka::VERSION} at #{Time.now}"
end
def generated_by_babushka
  "Generated #{_by_babushka}"
end
def edited_by_babushka
  "This line edited #{_by_babushka}"
end
def added_by_babushka nlines
  if nlines == 1
    "This line added #{_by_babushka}"
  else
    "These #{nlines} lines added #{_by_babushka}"
  end
end

def read_file filename
  path = pathify filename
  File.read(path).chomp if File.exists? path
end

def babushka_config? path
  if !File.exists?(path)
    unmet "the config hasn't been generated yet"
  elsif !grep(/Generated by babushka/, path)
    unmet "the config needs to be regenerated"
  else
    true
  end
end

def confirm message, &block
  answer = var("confirm - #{message}",
    :message => message.chomp('?'),
    :default => 'n'
  ).starts_with?('y')

  block.call if answer
end

require 'yaml'
def yaml path
  YAML.load_file pathify path
end

def render_erb erb, opts = {}
  path = File.dirname(source_path) / erb
  if !File.exists?(path) && !opts[:optional]
    log_error "Couldn't find erb to render at #{path}."
  elsif File.exists?(path)
    require 'erb'
    debug ERB.new(IO.read(path)).result(binding)
    returning shell("cat > #{opts[:to]}",
      :input => ERB.new(IO.read(path)).result(binding),
      :sudo => opts[:sudo]
    ) do |result|
      if result
        log "Rendered #{opts[:to]}."
        sudo "chmod #{opts[:perms]} '#{opts[:to]}'" unless opts[:perms].nil?
      else
        log_error "Couldn't render #{opts[:to]}."
      end
    end
  end
end

def log_and_open message, url
  log "#{message} Hit Enter to open the download page.", :newline => false
  read_from_prompt ' '
  shell "open #{url}"
end

def mysql cmd, username = 'root', include_password = true
  password_segment = "--password='#{var :db_password}'" if include_password
  shell "echo \"#{cmd.gsub('"', '\"').end_with(';')}\" | mysql -u #{username} #{password_segment}"
end
