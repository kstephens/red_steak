require 'rubygems'
require 'rake'
 
begin
  require 'echoe'
 
  $e = Echoe.new('redsteak', '0.1') do |p|
    # p.rubyforge_name = 'red_steak'
    p.summary = "RedSteak - A UML 2 Statemachine for Ruby."
    p.description = ""
    p.url = "http://red-steak.rubyforge.com/"
    p.author = ['Kurt Stephens']
    p.email = "ruby-redsteak@umleta.com"
    # p.dependencies = ["launchy"]
  end
 
rescue LoadError => boom
  puts "You are missing a dependency required for meta-operations on this gem."
  puts "#{boom.to_s.capitalize}."
end
 
# add spec tasks, if you have rspec installed
begin
  require 'spec/rake/spectask'
 
  ENV['PATH'] = "/var/lib/gems/1.8/bin:#{ENV['PATH']}"

  def spec_files
    @spec_files ||=
      (f = ENV['file']) ? [ f ] : FileList['test/**/*.spec'] + FileList['spec/**/*_spec.rb']
  end

  SPEC_OPTS = ['--backtrace', '-f n']
  if $stdout.tty? && ENV['TERM'] != 'dumb'
    # $stderr.puts ENV['TERM']
    SPEC_OPTS << '--color' 
  end


  Spec::Rake::SpecTask.new("spec") do |t|
    t.spec_files = spec_files
    t.spec_opts = SPEC_OPTS
  end
 
  task :test do
    Rake::Task['spec'].invoke
  end
 
  Spec::Rake::SpecTask.new("rcov_spec") do |t|
    t.spec_files = spec_files
    t.spec_opts = SPEC_OPTS
    t.rcov = true
    t.rcov_opts = ['--exclude', '^spec,/gems/']
  end
end

directory 'doc/example'

task :test => [ Rake::Task['doc/example'], :rcov_spec ] do
  # NOTHING
end

task :docs => :test do
  # NOTHING
end

VC_NAME = 'red_steak'
require 'lib/tasks/p4_git'
VC_OPTS[:manifest] = 'Manifest'


