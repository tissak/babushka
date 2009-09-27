dep 'passenger deploy repo' do
  requires 'git', 'user exists'
  met? { File.directory? pathify var(:passenger_repo_root) / '.git' }
  meet {
    FileUtils.mkdir_p pathify var(:passenger_repo_root) and
    in_dir var(:passenger_repo_root) do
      shell "git init"
      render_erb "git/deploy-repo-post-receive", :to => pathify(var(:passenger_repo_root) / '.git/hooks/post-receive')
      shell "chmod +x #{pathify var(:passenger_repo_root) / '.git/hooks/post-receive'}"
    end
  }
end

dep 'new git repo' do
  requires 'git', 'development dir'
  met? { File.directory? pathify var(:development_directory) / var(:new_project) / ".git" }
  meet {
    project_dir = pathify var(:development_directory) / var(:new_project)
    shell "mkdir #{project_dir}"
    in_dir project_dir do      
      shell "git init"
    end
  }
end

dep 'development dir' do
  met? { File.directory? pathify var(:development_directory) }
  meet {
    dev_dir = pathify var(:development_directory)
    shell "mkdir #{dev_dir}"
  }
end

dep 'standard git ignore' do 
  met? { File.file? pathify var(:rails_root) / ".gitignore" }
  meet {
    in_dir var(:rails_root) do
      render_erb "git/std_git_ignore", :to => pathify(var(:rails_root) / '.gitignore')
    end
  }
end

dep 'git full commit' do
  met? {
    in_dir var(:rails_root) do
      shell("git status") {|shell|
        shell.stdout.split("\n").grep(/Untracked/)
      }.empty?
    end
  }
  meet {
    in_dir var(:rails_root) do
      commit_message = var(:commit_message, :default=>'initial commit')
      shell "git add ."
      shell "git commit -a -m '#{commit_message}'"
    end
  }
end
