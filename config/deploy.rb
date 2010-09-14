set :application, "rubycas-server"
set :repository,  "git://github.com/dmcbrazil/rubycas-server.git"
set :branch, "origin/master"
set :user, "deploy"
set(:runner) { user }
set :use_sudo, false

set :scm, :git
set :git_enable_submodules, 1

set :deploy_to, "/var/www/apps/#{application}"
set :scm, :git

# Git settings for capistrano
default_run_options[:pty] = true 
ssh_options[:forward_agent] = true

set :stages, %w(development staging production)
set :default_stage, 'development'
# Capistrano Multistage (capistrano-ext)
require 'capistrano/ext/multistage'

def parse_config(file)
  require 'erb'  #render not available in Capistrano 2
  template=File.read(file)          # read it
  return ERB.new(template).result(binding)   # parse it
end

# Generates a configuration file parsing through ERB
# Fetches local file and uploads it to remote_file
# Make sure your user has the right permissions.
def generate_config(local_file,remote_file)
  temp_file = '/tmp/' + File.basename(local_file)
  buffer    = parse_config(local_file)
  File.open(temp_file, 'w+') { |f| f << buffer }
  upload temp_file, remote_file, :via => :scp
  `rm #{temp_file}`
end 

set(:server_bin_path) { "#{current_path}/bin/rubycas-server-ctl" }
set(:server_config_path) { "#{current_path}/config/config.yml" }
set(:server_pid_path) { "#{current_path}/tmp/rubycas-server.pid" }

set :shared_dirs, %w(config tmp pids log)

set :normal_symlinks, %w(
  config/config.yml
  log
  tmp
)

# Weird symlinks go somewhere else. Weird.
set :weird_symlinks, {
   'pids'   => 'tmp/pids'
}

namespace :deploy do
  
  
  desc "[Seppuku] Destroy everything"
  task :seppuku do
    run "rm -rf #{current_path}; rm -rf #{shared_path}"
    rubycas.seppuku
  end


  desc "Deploy the MFer"
  task :default do
    update
    restart
  end
  
  task :setup_dirs, :except => { :no_release => true } do
    commands = shared_dirs.map do |path|
      "mkdir -p #{shared_path}/#{path}"
    end
    run commands.join(" && ")
  end
  
  desc "Uploads your local config.yml to the server"
  task :configure, :except => { :no_release => true } do
    generate_config('config/config.yml', "#{shared_path}/config/config.yml")
  end
  
  desc "Setup a GitHub-style deployment."
  task :setup, :except => { :no_release => true } do
    run "rm -rf #{current_path}"
    setup_dirs
    run "git clone #{repository} #{current_path}"
  end

  desc "Update the deployed code."
  task :update_code, :except => { :no_release => true } do
    run "cd #{current_path}; git fetch origin; git reset --hard #{branch}"
  end
  
  namespace :rollback do
    desc "Rollback a single commit."
    task :default, :except => { :no_release => true } do
      set :branch, "HEAD^"
      deploy.default
    end    
  end
  
  task :start do; end
  task :stop do; end
  task :restart do; end
  task :migrate do; end
  
  task :symlink do
    commands = normal_symlinks.map do |path|
      "rm -rf #{current_path}/#{path} && \
       ln -s #{shared_path}/#{path} #{current_path}/#{path}"
    end

    commands += weird_symlinks.map do |from, to|
      "rm -rf #{current_path}/#{to} && \
       ln -s #{shared_path}/#{from} #{current_path}/#{to}"
    end if exists?(:weird_symlinks)
    
    run commands.join(" && ")
  end
  
  task :cleanup do; end
end

namespace :rubycas do
  set :init_local,  "resources/rubycas-server.erb"
  set :init_temp,   "/tmp/rubycas-server"
  set :init_remote, "/etc/init.d/rubycas-server"
  
  desc "Starts the Rubycas service"
  task :start, :roles => [:app] do
    run "service rubycas-server start"
  end

  desc "Stops the Rubycas service"
  task :stop, :roles => [:app] do
    run "service rubycas-server stop"
  end

  desc "Restarts the Rubycas service"
  task :restart, :roles => [:app] do
    run "service rubycas-server restart"
  end

  desc "Shows the Rubycas service status"
  task :status, :roles => [:app] do
    run "service rubycas-server status"
  end  
  
  desc "Bootstraps rubycas to init.d"
  task :bootstrap, :roles => [:app] do
    generate_config(init_local, init_temp)
    sudo "mv #{init_temp} #{init_remote}"
    sudo "chmod +x #{init_remote}"
    sudo "update-rc.d rubycas-server defaults"
    puts "Oikai! user cap rubycas:seppuku to revert."
  end
  
  desc "[Seppuku] Purges rubycas from init.d"
  task :seppuku, :roles => [:app] do
    sudo "update-rc.d -f rubycas-server remove"
    puts "Oikai! rubycas-server is gone from init.d"
  end
end
