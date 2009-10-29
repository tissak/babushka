dep 'user shell setup' do
  requires 'fish', 'dot files'
  met? { File.basename(sudo('echo \$SHELL', :as => var(:username), :su => true)) == 'fish' }
  meet { sudo "chsh -s #{shell('which fish')} #{var(:username)}" }
end

src 'fish' do
  requires 'ncurses', 'doc', 'coreutils', 'sed'
  source "git://github.com/benhoskings/fish.git"
  preconfigure { shell "autoconf" }
  configure_env { on :osx, "LDFLAGS='-liconv -L/opt/local/lib'" }
  configure_args "--without-xsel"
  after { append_to_file which('fish'), '/etc/shells' }
end

dep 'passwordless ssh logins' do
  requires 'user exists'
  met? { grep var(:your_ssh_public_key), '~/.ssh/authorized_keys' }
  meet {
    shell 'mkdir -p ~/.ssh'
    append_to_file var(:your_ssh_public_key), "~/.ssh/authorized_keys"
    shell 'chmod 700 ~/.ssh'
    shell 'chmod 600 ~/.ssh/authorized_keys'
  }
end

dep 'public key' do
  met? { grep /^ssh-dss/, '~/.ssh/id_dsa.pub' }
  meet { shell("ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ''").tap_log }
end

dep 'dot files' do
  requires 'user exists', 'git'
  met? { File.exists?(ENV['HOME'] / ".dot-files/.git") }
  meet { shell %Q{curl -L "http://github.com/#{var :github_user, :default => 'benhoskings'}/#{var :dot_files_repo, :default => 'dot-files'}/tree/master/clone_and_link.sh?raw=true" | bash} }
end

dep 'user exists' do
  on :osx do
    met? { !shell("dscl . -list /Users").split("\n").grep(var(:username)).empty? }
  end
  on :linux do
    met? { grep(/^#{var(:username)}:/, '/etc/passwd') }
    meet {
      sudo "mkdir -p #{var :home_dir_base}" and
      sudo "useradd #{var(:username)} -m -s /bin/bash -b #{var :home_dir_base} -G admin" and
      sudo "chmod 701 #{var(:home_dir_base) / var(:username)}"
    }
  end
end
