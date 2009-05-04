begin

  require 'lib/tasks/p4'

  VC_OPTS = { } unless defined? VC_OPTS
  VC_OPTS.
    update({
             :vc => 'SVN',
             :get_vc_root => lambda { | opts |
               `svn info`.split("\n").grep(/^URL: /).first.split(/\s+/)[-1]
             },
             :update => lambda { | opts | 
               sh "svn update"
             },
             :get_vc_id => lambda { | opts |
               `svn update`.chomp
             },
             :submit => lambda { | opts | 
               sh "svn ci -m #{opts[:vc_m].inspect}"
             },
           })

  desc "p4 edit; git pull origin master; p4 revert -a"
  task :p4_submit do
    p4_submit(VC_OPTS)
  end


  desc "p4 edit ...; git commit -a -m ...; p4 revert -a "
  task :p4_edit_svn_ci do
    p4_edit_vc_commit(VC_OPTS)
  end

end


