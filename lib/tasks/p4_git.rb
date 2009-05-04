begin

  require 'lib/tasks/p4'

  VC_OPTS = { } unless defined? VC_OPTS
  VC_OPTS.
    update({
             :vc => 'git',
             :get_vc_root => lambda { | opts |
               File.read('.git/FETCH_HEAD').split(/\s+/)[-1]
             },
             :update => lambda { | opts | 
               sh "git pull origin master"
             },
             :get_vc_id => lambda { | opts |
               git_revision
             },
             :submit => lambda { | opts | 
               sh "git commit -a -m #{opts[:vc_m].inspect}" 
             }
           })
  
  desc "Records current git commit id to .git_revision for p4 check-in"
  task :git_revision do
    puts git_revision
  end
  
  def git_revision 
    `git log | head -1 | tee .git_revision`.chomp
  end
  
  desc "p4 edit; git pull origin master; p4 revert -a"
  task :p4_git_commit do
    p4_submit(VC_OPTS)
  end

  desc "p4 edit ...; git commit -a -m ...; p4 revert -a "
  task :p4_edit_git_commit do
    p4_edit_vc_commit(VC_OPTS)
  end

end


