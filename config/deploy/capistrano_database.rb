#
# = Capistrano database.yml task
#
# Provides a couple of tasks for creating the database.yml
# configuration file dynamically when deploy:setup is run.
#
# Category::    Capistrano
# Package::     Database
# Author::      Simone Carletti
# Copyright::   2007-2009 The Authors
# License::     MIT License
# Link::        http://www.simonecarletti.com/
# Source::      http://gist.github.com/2769
#
# http://www.simonecarletti.com/blog/2009/06/capistrano-and-database-yml/
=begin
In case you need to run deploy:setup again and you don’t want Capistrano to ask for a database password, 
set the skip_db_setup option to true. This is especially useful in combination with capistrano multi-stage 
recipe when you already setup your server and you share the same environment across all the stages.

$ cap deploy:setup -s "skip_db_setup=true"
=end

unless Capistrano::Configuration.respond_to?(:instance)
  abort "This extension requires Capistrano 2"
end

Capistrano::Configuration.instance.load do

  namespace :db do

    desc <<-DESC
      Creates the database.yml configuration file in shared path.

      By default, this task uses a template unless a template
      called database.yml.erb is found either is :template_dir
      or /config/deploy folders. The default template matches
      the template for config/database.yml file shipped with Rails.

      When this recipe is loaded, db:setup is automatically configured
      to be invoked after deploy:setup. You can skip this task setting
      the variable :skip_db_setup to true. This is especially useful
      if you are using this recipe in combination with
      capistrano-ext/multistaging to avoid multiple db:setup calls
      when running deploy:setup for all stages one by one.
    DESC
    task :setup, :except => { :no_release => true } do

      default_template = <<-EOF
      base: &base
        adapter: sqlite3
        timeout: 5000
      development:
        database: #{shared_path}/db/development.sqlite3
        <<: *base
      test:
        database: #{shared_path}/db/test.sqlite3
        <<: *base
      production:
        database: #{shared_path}/db/production.sqlite3
        <<: *base
      EOF
      
      location = fetch(:template_dir, "config/deploy") + '/database.yml.erb'
      template = File.file?(location) ? File.read(location) : default_template

      config = ERB.new(template)

      puts "capistrano_database.rb: mkdir -p #{shared_path}/db"
      run "mkdir -p #{shared_path}/db"
      puts "capistrano_database.rb: mkdir -p #{shared_path}/config"
      run "mkdir -p #{shared_path}/config"
      puts "capistrano_database.rb: 'config.result(binding)', #{shared_path}/config/database.yml"
      put config.result(binding), "#{shared_path}/config/database.yml"
    end

    desc <<-DESC
      [internal] Updates the symlink for database.yml file to the just deployed release.
    DESC
    task :symlink, :except => { :no_release => true } do
      puts "capistrano_database.rb: symlinking database.yml: ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
      run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    end

  end

  puts "capistano_database.rb: NEXT: db:setup"
  after "deploy:setup",           "db:setup"   unless fetch(:skip_db_setup, false)
  # This runs during a basic deploy, not "cap deploy:setup"
  puts "capistano_database.rb: NEXT: after deploy:finalize_update, db:symlink"
  after "deploy:finalize_update", "db:symlink"

end