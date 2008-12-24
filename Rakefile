

task :default => :test do
end

task :test do
  ENV['RUBYLIB'] = ($: + [ 'lib' ]) * ':'
  Dir['test/*.spec'].each do | t |
    sh "spec -f specdoc #{t}"
  end
end

