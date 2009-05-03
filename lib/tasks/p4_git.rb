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
