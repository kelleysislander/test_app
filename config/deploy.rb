=begin
In case you need to run deploy:setup again and you don’t want Capistrano to ask for a database password, 
set the skip_db_setup option to true. This is especially useful in combination with capistrano multi-stage 
recipe when you already setup your server and you share the same environment across all the stages.

$ cap deploy:setup -s "skip_db_setup=true"

=end

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'deploy')

set :stages, %w(staging production)
set :default_stage, "staging"

require 'bundler/capistrano'
require 'capistrano/ext/multistage'
puts "deploy.rb: require capistrano_database"
require "capistrano_database"

$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
require "rvm/capistrano"
require 'bundler/capistrano'

puts "ENV['rvm_path']"
puts ENV['rvm_path']

puts "ENV['rails_env']"
puts ENV['rails_env']

puts "END ENV['rvm_path']"

$:.unshift(File.expand_path('./lib', ENV['rvm_path']))  # Add RVM's lib directory to the load path.
require "rvm/capistrano"                                # Load RVM's capistrano plugin.
set :rvm_ruby_string, '1.9.2-p290@test_app'               # Or whatever env you want it to run in.
set :rvm_bin_path, "$HOME/.rvm/bin"
set :rvm_type, :user

set :default_environment, {
  'PATH' => "/home/deploy/.rvm/gems/ruby-1.9.2-p290/bin:/home/deploy/.rvm/gems/ruby-1.9.2-p290@global/bin:/home/deploy/.rvm/rubies/ruby-1.9.2-p290/bin:/home/deploy/.rvm/bin:$PATH",
  'RUBY_VERSION' => 'ruby-1.9.2-p290',
  'GEM_HOME'     => '/home/deploy/.rvm/gems/ruby-1.9.2-p290',
  'GEM_PATH'     => '/home/deploy/.rvm/gems/ruby-1.9.2-p290:/home/deploy/.rvm/gems/ruby-1.9.2-p290@global',
  'BUNDLE_PATH'  => '/home/deploy/.rvm/gems/ruby-1.9.2-p290'  # If you are using bundler.
}

namespace :deploy do

  # NOTE:  the variables RAILS_SHARED_PATH, RAILS_CURRENT_PATH are used to pass their values into wheneverize's schedule.rb
  desc "Update crontab from whenever configuration"
  task :wheneverize, :roles => :db do
    if rails_env == "production"
      run "cd #{current_path} && RAILS_ENV=#{rails_env} RAILS_SHARED_PATH=#{shared_path} RAILS_CURRENT_PATH=#{current_path} bundle exec whenever --update-crontab #{application}"
    end
  end

  desc "Create VHost Apache"
  task :create_vhost_apache do
    vhost = <<-EOF
    <VirtualHost *:80>
      ServerAlias #{app_uri}
      DocumentRoot #{deploy_to}/current/public
#      SetEnv GEM_HOME #{gem_home}
#      SetEnv GEM_PATH #{gem_path}
      <Directory #{deploy_to}/current/public>
         AllowOverride all
         Options -MultiViews
      </Directory>

      RailsEnv #{rails_env}
    </VirtualHost>
    EOF

    put vhost, "#{release_path}/config/vhost"
    sudo "mv #{release_path}/config/vhost /etc/apache2/sites-available/#{app_uri}"
    sudo "a2ensite #{app_uri}"
    sudo "/etc/init.d/apache2 reload"
  end

  desc "Create VHost Nginx"
  task :create_vhost_nginx do
    vhost = <<-EOF
    server {
      listen 80;
      server_name #{app_uri};

      access_log #{deploy_to}/current/log/access.log;
      error_log #{deploy_to}/current/log/error.log;

      root #{deploy_to}/current/public;
      passenger_enabled on;
      rails_env #{rails_env};

      location /system {
        auth_basic "Restricted";
        auth_basic_user_file #{deploy_to}/current/.htpasswd;
      }
    }
    EOF

    put vhost, "#{release_path}/config/vhost"
    # sudo "rm /opt/nginx/sites-available/#{app_uri} /opt/nginx/sites-enabled/#{app_uri}"
    sudo "mv -f #{release_path}/config/vhost /etc/nginx/sites-available/#{app_uri}"
    sudo "ln -f -s /etc/nginx/sites-available/#{app_uri} /opt/nginx/sites-enabled/#{app_uri}"
    sudo "/etc/init.d/nginx reload"
  end


  desc "Restarting mod_rails with restart.txt"
  task :restart, :roles => :app, :except => { :no_release => true } do
    puts "running => task :restart, :roles => :app, :except => { :no_release => true }"
    run "touch #{current_path}/tmp/restart.txt"
  end

  namespace :nginx do
    desc "Reload Nginx"
    task :reload do
      sudo "/etc/init.d/nginx reload"
    end
  end

  namespace :db do
    desc 'Migrate DB down, up, seed'
    task :reseed do
      run "cd #{current_path} && RAILS_ENV=#{rails_env} rake db:migrate VERSION=0 && RAILS_ENV=#{rails_env} rake db:migrate && RAILS_ENV=#{rails_env} rake db:seed"
    end
  end

  # namespace :rvmrc do
  #   task :symlink do
  #     puts "************* Running deploy:rvmrc:symlink #{rvm_ruby_string}, #{release_path}, #{shared_path}"
  #     run "ls -al #{release_path}"
  #     # put "rvm --create use #{rvm_ruby_string}", "#{release_path}/.rvmrc"
  #   end
  # end

  desc 'moves the current .rvmrc into #{shared_path/config/.rvmrc and symlinks it'
  namespace :rvmrc do
    task :symlink, :except => { :no_release => true } do
      puts "************ running: deploy.rb: symlinking .rvmrc: ln -nfs #{shared_path}/config/.rvmrc #{release_path}/config/.rvmrc"
      run "cp -vf #{release_path}/.rvmrc #{shared_path}/config/.rvmrc"
      puts "************ running: ln -nfs #{shared_path}/config/.rvmrc #{release_path}/.rvmrc"
      run "ln -nfs .rvmrc #{shared_path}/config/.rvmrc"
      # run "ln -nfs #{shared_path}/config/.rvmrc #{release_path}/.rvmrc"
    end
  end
end

  # # after "deploy", "rvmrc:create"
# before "deploy:finalize_update",     "deploy:rvmrc:symlink"
after "deploy:cleanup",             "deploy:create_vhost_nginx"
after "deploy:create_vhost_nginx",  "deploy:nginx:reload"

=begin
NOTE:  To run the 'capistrano_database.rb' you do a:
  
  cap deploy:setup
  
To run setup again and avoid inputting the db pwd do a:
  
  cap deploy:setup -s "skip_db_setup=true"
  

=end
# don't run these next 2 tasks the very first time a deploy is done since the target of the symlink must be moved into place after the first deploy
# after "deploy:migrations", "deploy:cleanup"
# after "deploy:symlink_configs", "deploy:cleanup"
# after "nginx:reload", "thin:restart"

# after "deploy:wheneverize","deploy:prepare_delayed_jobs"
# after "deploy:symlink_uploads", "deploy:symlink_configs"
# after "deploy", "deploy:symlink_uploads"
# after "deploy", "deploy:wheneverize"

=begin
On the remote server:

Creates the remote rvm symlink because rvm was installed in /home/deploy instead of /usr/local which is the proper palce to put a global executable
cd /usr/local && ln -s ~/.rvm rvm

Creates the symlink for the rvm-shell variable which loads a bash shell and RVM which the rest of capistrano runs inside
cd /usr/local/bin && ln -s rvm-shell ../rvm/bin/rvm-shell

For the case where the remote machine has a current folder that is not a symlink:
mv current current-old && ln -s current-old current
Which will move the old folder and quickly symlink it so that capistrano will not accidently delete your directory

=end

#  * executing `deploy'
#  * executing `deploy:update'
# ** transaction: start
#  * executing `deploy:update_code'

# set :stages, %w(staging production)
# set :default_stage, "staging"
# 
# require 'capistrano/ext/multistage'
# require 'bundler/capistrano'
# 
# # ln -s ~/.rvm rvm
# $:.unshift(File.expand_path('./lib', ENV['rvm_path']))
# require "rvm/capistrano"
# set :rvm_ruby_string, '1.9.2-p180@irival'
# 
# namespace :deploy do
# 
#   desc "deploy:update"
#   task :update do 
#     puts "running => deploy:update"
#   end
#   
#   desc "Link the config files into the current release path."
#   task :symlink_configs, roles: :app, except: {:no_release => true} do
# 
#     puts "running => task :symlink_configs"
#     # run <<-CMD
#     #   cd #{latest_release} &&
#     #   ln -nfs #{shared_path}/config/database.yml #{latest_release}/config/database.yml
#     # CMD
#   end
# 
# 
#   desc "Create VHost Apache"
#   task :create_vhost_apache do
# 
#     puts "running => task :create_vhost_apache"
# #     vhost = <<-EOF
# #     <VirtualHost *:80>
# #       ServerAlias #{app_uri}
# #       DocumentRoot #{deploy_to}/current/public
# # #      SetEnv GEM_HOME #{gem_home}
# # #      SetEnv GEM_PATH #{gem_path}
# #       <Directory #{deploy_to}/current/public>
# #          AllowOverride all
# #          Options -MultiViews
# #       </Directory>
# # 
# #       RailsEnv #{rails_env}
# #     </VirtualHost>
# #     EOF
# # 
# #     put vhost, "#{release_path}/config/vhost"
# #     sudo "mv #{release_path}/config/vhost /etc/apache2/sites-available/#{app_uri}"
# #     sudo "a2ensite #{app_uri}"
# #     sudo "/etc/init.d/apache2 reload"
#   end
# 
#   desc "Create VHost Nginx"
#   task :create_vhost_nginx do
#     
#     puts "running => task :create_vhost_nginx"
#     # vhost = <<-EOF
#     # server {
#     #   listen 80;
#     #   server_name #{app_uri};
#     # 
#     #   access_log #{deploy_to}/current/log/access.log;
#     #   error_log #{deploy_to}/current/log/error.log;
#     # 
#     #   root #{deploy_to}/current/public;
#     #   passenger_enabled on;
#     #   rails_env #{rails_env};
#     # 
#     #   location /system {
#     #     auth_basic "Restricted";
#     #     auth_basic_user_file #{deploy_to}/current/.htpasswd;
#     #   }
#     # }
#     # EOF
#     # 
#     # put vhost, "#{release_path}/config/vhost"
#     # # sudo "rm /opt/nginx/sites-available/#{app_uri} /opt/nginx/sites-enabled/#{app_uri}"
#     # sudo "mv -f #{release_path}/config/vhost /opt/nginx/sites-available/#{app_uri}"
#     # sudo "ln -f -s /opt/nginx/sites-available/#{app_uri} /opt/nginx/sites-enabled/#{app_uri}"
#     # sudo "/etc/init.d/nginx reload"
#   end
# 
#   desc "Restarting mod_rails with restart.txt"
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     puts "running => task :restart, :roles => :app, :except => { :no_release => true }"
# 
#     # run "touch #{current_path}/tmp/restart.txt"
#   end
# 
#   # [:start, :stop].each do |t|
#   #   desc "#{t} task is a no-op with mod_rails"
#   #   task t, :roles => :app do ; end
#   # end
# end
# 
# namespace :rvmrc do
#   task :create, :roles => :app do
#     puts "running => task :create, :roles => :app"
#     # put "rvm --create use #{rvm_ruby_string}", "#{release_path}/.rvmrc"
#   end
# end
# 
# namespace :permissions do
# end
# 
# 
# # after "deploy", "rvmrc:create"
# after "deploy:update_code", "deploy:symlink_configs"
# 


# If you are using Passenger mod_rails uncomment this:
# if you're still using the script/reapear helper you will need
# these http://github.com/rails/irs_process_scripts

# namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
#   end
# end