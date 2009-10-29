require 'spec/spec_support'

SucceedingLs = 'ls /bin'
FailingLs = 'ls /nonexistent'

describe "shell" do
  it "should return something true on successful commands" do
    shell('true').should_not be_nil
  end
  it "should return nil on failed commands" do
    shell('false').should be_nil
  end
  it "should return output of successful commands" do
    shell('echo lol').should == 'lol'
  end
  it "should provide the shell to supplied blocks" do
    shell(SucceedingLs) {|shell|
      shell.stdout.should include 'bash'
      shell.stderr.should be_empty
    }
    shell(FailingLs) {|shell|
      shell.stdout.should be_empty
      shell.stderr.should include "No such file or directory"
    }
  end
  it "should accept :input parameter" do
    shell('cat', :input => 'lol').should == "lol"
  end
end

describe "failable_shell" do
  it "should always return a Shell" do
    failable_shell('true').should be_a Shell
    failable_shell('false').should be_a Shell
  end
  it "should return stderr for failed commands" do
    shell = failable_shell(FailingLs)
    shell.stdout.should be_empty
    shell.stderr.should include "No such file or directory"
  end
end

describe "sudo" do
  before {
    @current_user = `whoami`.chomp
  }
  it "should run as root when no user is given" do
    sudo('whoami').should == 'root'
  end
  it "should run as the given user" do
    sudo('whoami', :as => @current_user).should == @current_user
  end
  describe "compound commands" do
    it "should use 'sudo su -' when opts[:su] is supplied" do
      sudo("echo \\`whoami\\`", :su => true).should == 'root'
    end
    describe "redirects" do
      before {
        @tmp_path = tmp_prefix / 'su_with_redirect'
        sudo "rm #{@tmp_path}"
      }
      it "should use 'sudo su -'" do
        sudo("echo \\`whoami\\` > #{@tmp_path}")
        File.read(@tmp_path).chomp.should == 'root'
        File.owner(@tmp_path).should == 'root'
      end
    end
    describe "pipes" do
      before {
        @tmp_path = tmp_prefix / 'su_with_redirect'
        sudo "rm #{@tmp_path}"
      }
      it "should use 'sudo su -'" do
        sudo("echo \\`whoami\\` | tee #{@tmp_path}")
        File.read(@tmp_path).chomp.should == 'root'
        File.owner(@tmp_path).should == 'root'
      end
    end
  end
end

describe "log_shell" do
  before {
    should_receive(:log).exactly(2).times
  }
  it "should log and run a command" do
    should_receive(:shell).with('uptime', {})
    log_shell 'Getting uptime', 'uptime'
  end
  it "should log correctly for a failing command" do
    should_receive(:shell).with('nonexistent', {})
    log_shell 'Nonexistent shell command', 'nonexistent'
  end
end

describe "grep" do
  it "should grep existing files" do
    grep('include', 'spec/spec_support.rb').should include "include Babushka\n"
  end
  it "should return nil when there are no matches" do
    grep('lol', 'spec/spec_support.rb').should be_nil
  end
  it "should return nil for nonexistent files" do
    grep('lol', '/nonexistent').should be_nil
  end
end

describe "which" do
  it "should return the path for valid commands" do
    path = `which ls`.chomp
    which('ls').should == path
  end
  it "should return nil for nonexistent commands" do
    which('nonexistent').should be_nil
  end
end

require 'fileutils'
describe "in_dir" do
  before do
    @tmp_dir = tmp_prefix
    FileUtils.mkdir_p @tmp_dir
    @tmp_dir_2 = File.join(tmp_prefix, '2')
    FileUtils.mkdir_p @tmp_dir_2

    @original_pwd = Dir.pwd

    @nonexistent_dir = File.join(tmp_prefix, 'nonexistent')
    Dir.rmdir(@nonexistent_dir) if File.directory?(@nonexistent_dir)
  end

  it "should yield if no chdir is required" do
    has_yielded = false
    in_dir(@original_pwd) {
      Dir.pwd.should == @original_pwd
      has_yielded = true
    }
    has_yielded.should be_true
  end
  it "should change dir for the duration of the block" do
    has_yielded = false
    in_dir(@tmp_dir) {
      Dir.pwd.should == @tmp_dir
      has_yielded = true
    }
    has_yielded.should be_true
    Dir.pwd.should == @original_pwd
  end
  it "should work recursively" do
    in_dir(@tmp_dir) {
      Dir.pwd.should == @tmp_dir
      in_dir(@tmp_dir_2) {
        Dir.pwd.should == @tmp_dir_2
      }
      Dir.pwd.should == @tmp_dir
    }
    Dir.pwd.should == @original_pwd
  end
  it "should fail on nonexistent dirs" do
    L{ in_dir(@nonexistent_dir) }.should raise_error Errno::ENOENT
  end
  it "should create nonexistent dirs if :create => true is specified" do
    in_dir(@nonexistent_dir, :create => true) {
      Dir.pwd.should == @nonexistent_dir
    }
    Dir.pwd.should == @original_pwd
  end
end

describe "in_build_dir" do
  before {
    @original_pwd = Dir.pwd
  }
  it "should change to the build dir with no args" do
    in_build_dir {
      Dir.pwd.should == pathify("~/.babushka/src")
    }
    Dir.pwd.should == @original_pwd
  end
  it "should append the supplied path when supplied" do
    in_build_dir "tmp" do
      Dir.pwd.should == pathify("~/.babushka/src/tmp")
    end
    Dir.pwd.should == @original_pwd
  end
end

describe "cmd_dir" do
  it "should return the cmd_dir of an existing command" do
    cmd_dir('ruby').should == `which ruby`.chomp.gsub(/\/ruby$/, '')
  end
  it "should return nil for nonexistent commands" do
    cmd_dir('nonexistent').should be_nil
  end
end
