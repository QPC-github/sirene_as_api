require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
require 'mina/rbenv'
require 'colorize'

ENV['domain'] || raise('no domain provided'.red)

ENV['to'] ||= 'sandbox'
raise("target environment (#{ENV['to']}) not in the list") unless %w[sandbox production].include?(ENV['to'])

print "Deploy to #{ENV['to']}\n".green

set :commit, ENV['commit']
set :application_name, 'sirene_api'
set :domain, ENV['domain']

set :deploy_to, "/var/www/sirene_api_#{ENV['to']}"
set :rails_env, ENV['to']

set :forward_agent, true
set :port, 22
set :repository, 'https://github.com/etalab/sirene_as_api.git'

branch = ENV['branch'] || case ENV['to']
  when 'production'
    'master'
  when 'sandbox'
    'develop'
  else
    abort 'Environment must be set to sandbox or production'
  end

set :branch, branch

# shared dirs and files will be symlinked into the app-folder by the 'deploy:link_shared_paths' step.
set :shared_dirs, fetch(:shared_dirs, []).push(
  'bin',
  'log',
  'public/system',
  'public/uploads',
  'tmp/cache',
  'tmp/files',
  'tmp/pids',
  'tmp/sockets',
  '.last_monthly_stock_applied'
)

set :shared_files, fetch(:shared_files, []).push(
  'config/database.yml',
  "config/environments/#{ENV['to']}.rb",
  'config/secrets.yml',
  'config/switch_server.yml',
  'config/sidekiq.yml',
  'config/sunspot.yml'
)

# This task is the environment that is loaded for all remote run commands, such as
# `mina deploy` or `mina rake`.
task :remote_environment do
  set :rbenv_path, '/usr/local/rbenv'
  invoke :'rbenv:load'
end

task :samhain_db_update do
  command %{sudo /usr/local/sbin/update-samhain-db.sh "#{fetch(:deploy_to)}"}
end

# Put any custom commands you need to run at setup
# All paths in `shared_dirs` and `shared_paths` will be created on their own.
task :setup do
  invoke :'ownership'
  invoke :'samhain_db_update'
end

desc 'Deploys the current version to the server.'
task deploy: :remote_environment do
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'ownership'

    on :launch do
      in_path(fetch(:current_path)) do
        command %{mkdir -p tmp/}
        command %{touch tmp/restart.txt}
        invoke :'ownership'
        invoke :solr
      end

      invoke :sidekiq
      invoke :passenger
    end
  end
  invoke :'samhain_db_update'
end

task solr: :remote_environment do
  comment 'Restarting Solr service'.green
  command 'sudo systemctl restart solr'
end

task :sidekiq do
  comment 'Restarting Sidekiq (reloads code)'.green
  command %{sudo systemctl restart sidekiq_sirene_api_#{ENV['to']}_1}
end

task passenger: :remote_environment do
  comment %{Attempting to start Passenger app}.green
  command %{
    if (sudo passenger-status | grep sirene_api_#{ENV['to']}) >/dev/null
    then
      sudo passenger-config restart-app /var/www/sirene_api_#{ENV['to']}/current
    else
      echo 'Skipping: no passenger app found (will be automatically loaded)'
    fi
  }
end

task :ownership do
  command %{sudo chown -R deploy "#{fetch(:deploy_to)}"}
end
