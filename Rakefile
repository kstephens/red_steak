
######################################################################

CURRENT_DIR = File.expand_path(File.dirname(__FILE__))

######################################################################

PKG_Name = 'red_steak'
PKG_Author = 'Kurt Stephens'
PKG_Email = 'ruby-red_steak@umleta.com'
PKG_DESCRIPTION = %{RedSteak - A UML 2 Compliant Statemachine.

For more details, see:

http://rubyforge.org/projects/red_steak
http://redsteak.rubyforge.org/
http://redsteak.rubyforge.org/files/README_txt.html

}
PKG_lib_ruby_dir = 'lib/ruby'
PKG_manifest_reject = %r{example/.*/gems/.*/gems|example/doc|gen/rdoc}

######################################################################


$:.unshift "#{CURRENT_DIR}/lib/ruby"

require 'rubygems'


desc "Runs tests"
task :default => [ :test ] do
end

desc "Runs tests"
task :test do
  sh "mkdir -p example"
  gem_bin_path = Gem.path.map{|x| "#{x}/bin"}
  ENV['RUBYLIB'] = ($: + [ 'lib' ]) * ':'
  Dir[ENV['test'] || 'test/*.spec'].each do | t |
    sh "PATH=#{gem_bin_path * ':'}:$PATH spec -f specdoc #{t}"
  end
end


    ############################################################
    # Doco

begin
  require 'rdoc/task'
rescue LoadError
  require 'rake/rdoctask'
end

Rake::RDocTask.new(:docs) do |rd|
  name = 'red_steak'
  version = '0.1'
  rubyforge_name = name
  readme_file = 'README.txt'
  spec = OpenStruct.new(:require_paths => [ 'lib' ], :extra_rdoc_files => [ ])
  WINDOZE = false

      rd.main = readme_file
      rd.options << '-d' if (`which dot` =~ /\/dot/) unless
        ENV['NODOT'] || WINDOZE
      rd.rdoc_dir = 'doc'

      rd.rdoc_files += spec.require_paths
      rd.rdoc_files += spec.extra_rdoc_files

      title = "#{name}-#{version} Documentation"
      title = "#{rubyforge_name}'s " + title if rubyforge_name != name

      rd.options << "-t" << title
    end


desc "Records current git commit id to .git_revision for p4 check-in"
task :git_revision do
  git_revision
end

def git_revision 
  sh "git log | head -1 > .git_revision"
end

desc "p4 edit; git pull origin master; p4 revert -a"
task :p4_git_pull do
  sh "p4 edit ..."
  sh "git pull origin master"
  git_revision
  sh "find . -type f | grep -v ./.git | xargs p4 add"
  sh "p4 revert example/..."
  sh "p4 revert doc/..."
  sh "p4 revert -a ..."
end


# require "#{CURRENT_DIR}/rake_helper.rb"
